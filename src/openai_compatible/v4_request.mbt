///|
fn parse_compatible_v4_chat_options(
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
) -> ParsedOpenAICompatibleChatOptions {
  let resolution = resolve_compatible_options(
    options.provider_options,
    provider_name,
    chat_reserved_fields(),
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let user = reader.take_string("user")
  let reasoning_effort = reader.take_string("reasoningEffort", aliases=[
    "reasoning_effort",
  ])
  let text_verbosity = reader.take_string("textVerbosity", aliases=["verbosity"])
  let strict_json_schema = reader.take_bool("strictJsonSchema", aliases=[
    "strict_json_schema",
  ])
  {
    options: {
      user,
      reasoning_effort,
      text_verbosity,
      strict_json_schema,
      extensions: reader.remaining_values(),
    },
    warnings: reader.diagnostics(),
  }
}

///|
fn openai_compatible_v4_reasoning_effort(
  effort : @provider.LanguageModelV4ReasoningEffort,
) -> String? {
  match effort {
    @provider.V4ReasoningProviderDefault | @provider.V4ReasoningNone => None
    @provider.V4ReasoningMinimal => Some("minimal")
    @provider.V4ReasoningLow => Some("low")
    @provider.V4ReasoningMedium => Some("medium")
    @provider.V4ReasoningHigh => Some("high")
    @provider.V4ReasoningXHigh => Some("xhigh")
  }
}

///|
fn compatible_v4_tool_definition_to_json(
  tool : @provider.LanguageModelV4Tool,
) -> Json? {
  match tool {
    @provider.V4FunctionTool(value) => {
      let function = Json::object(
        Map(
          [
            ("name", Json::string(value.name)),
            ..if value.description is Some(description) {
              [("description", Json::string(description))]
            },
            ("parameters", value.input_schema),
            ..if value.strict is Some(strict) {
              [("strict", Json::boolean(strict))]
            },
          ],
        ),
      )
      Some(({ "type": "function", "function": function } : Json))
    }
    @provider.V4ProviderTool(_) => None
  }
}

///|
fn compatible_v4_tool_choice_to_json(
  choice : @provider.LanguageModelV4ToolChoice,
) -> Json {
  match choice {
    @provider.V4ToolChoiceAuto => Json::string("auto")
    @provider.V4ToolChoiceNone => Json::string("none")
    @provider.V4ToolChoiceRequired => Json::string("required")
    @provider.V4ToolChoiceTool(name) =>
      { "type": "function", "function": { "name": name } }
  }
}

///|
fn compatible_v4_response_format_to_json(
  format : @provider.LanguageModelV4ResponseFormat,
  supports_structured_outputs : Bool,
  strict_override : Bool?,
) -> Json? {
  match format {
    @provider.V4ResponseText => None
    @provider.V4ResponseJson(config) =>
      match config.schema {
        Some(schema) if supports_structured_outputs => {
          let json_schema : Map[String, Json] = Map([
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(strict_override.unwrap_or(true))),
          ])
          if config.description is Some(value) {
            json_schema["description"] = Json::string(value)
          }
          Some({
            "type": "json_schema",
            "json_schema": Json::object(json_schema),
          })
        }
        _ => Some(({ "type": "json_object" } : Json))
      }
  }
}

///|
fn compatible_v4_chat_request_warnings(
  options : @provider.LanguageModelV4CallOptions,
  parsed : ParsedOpenAICompatibleChatOptions,
  supports_structured_outputs : Bool,
  supports_top_k : Bool,
  supports_frequency_penalty : Bool,
) -> Array[@provider.Warning] {
  let warnings = parsed.warnings.copy()
  if !supports_top_k && options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  if !supports_frequency_penalty && options.frequency_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="frequencyPenalty",
        details="This OpenAI-compatible provider does not support frequencyPenalty.",
      ),
    )
  }
  for tool in options.tools {
    match tool {
      @provider.V4ProviderTool(value) =>
        warnings.push(
          @provider.Warning::unsupported("provider-defined tool \{value.id}"),
        )
      _ => ()
    }
  }
  if options.response_format
    is @provider.V4ResponseJson({ schema: Some(_), .. }) &&
    !supports_structured_outputs {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="responseFormat",
        details="JSON response format schema is only supported with structuredOutputs",
      ),
    )
  }
  warnings
}

///|
fn encode_compatible_v4_chat_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  messages : Array[Json],
  provider_options : OpenAICompatibleChatOptions,
  include_usage : Bool,
  stream : Bool,
  supports_structured_outputs : Bool,
  supports_top_k : Bool,
  supports_frequency_penalty : Bool,
) -> Json {
  let reasoning_effort = match provider_options.reasoning_effort {
    Some(value) => Some(value)
    None => openai_compatible_v4_reasoning_effort(options.reasoning)
  }
  let tools : Array[Json] = []
  for tool in options.tools {
    if compatible_v4_tool_definition_to_json(tool) is Some(value) {
      tools.push(value)
    }
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("messages", Json::array(messages)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if stream && include_usage {
        [("stream_options", ({ "include_usage": true } : Json))]
      },
      ..if options.max_output_tokens is Some(value) {
        [("max_tokens", Json::number(value.to_double()))]
      },
      ..if options.temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if options.top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if supports_top_k && options.top_k is Some(value) {
        [("top_k", Json::number(value))]
      },
      ..if supports_frequency_penalty &&
        options.frequency_penalty is Some(value) {
        [("frequency_penalty", Json::number(value))]
      },
      ..if options.presence_penalty is Some(value) {
        [("presence_penalty", Json::number(value))]
      },
      ..if options.seed is Some(value) {
        [("seed", Json::number(value.to_double()))]
      },
      ..if options.stop_sequences.length() > 0 {
        [
          (
            "stop",
            Json::array(
              [
                for stop in options.stop_sequences => Json::string(stop)
              ],
            ),
          ),
        ]
      },
      ..if provider_options.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if reasoning_effort is Some(value) {
        [("reasoning_effort", Json::string(value))]
      },
      ..if provider_options.text_verbosity is Some(value) {
        [("verbosity", Json::string(value))]
      },
    ],
  )
  if options.tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    if options.tool_choice is Some(choice) {
      fields["tool_choice"] = compatible_v4_tool_choice_to_json(choice)
    }
  }
  if compatible_v4_response_format_to_json(
      options.response_format,
      supports_structured_outputs,
      provider_options.strict_json_schema,
    )
    is Some(format) {
    fields["response_format"] = format
  }
  for entry in provider_options.extensions.iter2() {
    fields[chat_option_wire_key(entry.0)] = entry.1
  }
  Json::object(fields)
}

///|
/// Prepare an OpenAI-compatible request directly from the V4 contract.
fn prepare_compatible_v4_chat_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  include_usage : Bool,
  stream : Bool,
  provider_name : String,
  supports_structured_outputs : Bool,
  supports_top_k : Bool,
  supports_frequency_penalty : Bool,
  prompt_converter : OpenAICompatibleV4PromptConverter,
) -> OpenAICompatiblePreparedChatRequest raise {
  let parsed = parse_compatible_v4_chat_options(options, provider_name)
  let conversion = prompt_converter(options.prompt, provider_name)
  let warnings = compatible_v4_chat_request_warnings(
    options, parsed, supports_structured_outputs, supports_top_k, supports_frequency_penalty,
  )
  for warning in conversion.warnings {
    warnings.push(warning)
  }
  {
    body: encode_compatible_v4_chat_request(
      model_id,
      options,
      conversion.messages,
      parsed.options,
      include_usage,
      stream,
      supports_structured_outputs,
      supports_top_k,
      supports_frequency_penalty,
    ),
    warnings,
    metadata_key: @provider_utils.resolve_provider_options_key(
      compatible_provider_options_name(provider_name),
      options.provider_options,
    ),
  }
}

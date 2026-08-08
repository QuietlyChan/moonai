///|
priv struct OpenResponsesV4PreparedRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn open_responses_v4_reasoning_effort_value(
  effort : @provider.LanguageModelV4ReasoningEffort,
  warnings : Array[@provider.Warning],
) -> String? {
  match effort {
    @provider.V4ReasoningProviderDefault => None
    @provider.V4ReasoningNone => Some("none")
    _ =>
      @provider_utils.map_reasoning_to_provider_effort(
        effort.to_reasoning_effort(),
        {
          "minimal": "low",
          "low": "low",
          "medium": "medium",
          "high": "high",
          "xhigh": "xhigh",
        },
        warnings,
      )
  }
}

///|
fn open_responses_v4_reasoning(
  provider_options : OpenResponsesOptions,
  reasoning_effort : String?,
) -> Json? {
  let reasoning : Map[String, Json] = Map([])
  if provider_options.reasoning_summary is Some(value) {
    reasoning["summary"] = Json::string(value)
  }
  if reasoning_effort is Some(value) {
    reasoning["effort"] = Json::string(value)
  }
  if reasoning.length() == 0 {
    None
  } else {
    Some(Json::object(reasoning))
  }
}

///|
fn open_responses_v4_tool_to_json(
  tool : @provider.LanguageModelV4Tool,
) -> Json? {
  match tool {
    @provider.V4FunctionTool(value) =>
      Some(
        Json::object(
          Map(
            [
              ("type", Json::string("function")),
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
        ),
      )
    @provider.V4ProviderTool(_) => None
  }
}

///|
fn open_responses_v4_tool_choice_to_json(
  choice : @provider.LanguageModelV4ToolChoice,
) -> Json {
  match choice {
    @provider.V4ToolChoiceAuto => Json::string("auto")
    @provider.V4ToolChoiceNone => Json::string("none")
    @provider.V4ToolChoiceRequired => Json::string("required")
    @provider.V4ToolChoiceTool(name) => { "type": "function", "name": name }
  }
}

///|
fn open_responses_v4_text_format_to_json(
  format : @provider.LanguageModelV4ResponseFormat,
) -> Json? {
  match format {
    @provider.V4ResponseText => None
    @provider.V4ResponseJson(config) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("json_schema")),
      ])
      match config.schema {
        Some(schema) => {
          fields["name"] = Json::string(config.name.unwrap_or("response"))
          if config.description is Some(value) {
            fields["description"] = Json::string(value)
          }
          fields["schema"] = schema
          fields["strict"] = Json::boolean(true)
        }
        None => ()
      }
      Some(({ "format": Json::object(fields) } : Json))
    }
  }
}

///|
fn resolve_open_responses_v4_request_diagnostics(
  options : @provider.LanguageModelV4CallOptions,
  parsed : ParsedOpenResponsesOptions,
  prompt_warnings : Array[@provider.Warning],
) -> (Array[@provider.Warning], String?) {
  let warnings = parsed.warnings.copy()
  if options.stop_sequences.length() > 0 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="stopSequences",
        details="Open Responses has no portable stop-sequences field.",
      ),
    )
  }
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="The Responses protocol does not define a top-k sampling field.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="The Responses protocol does not define a seed setting.",
      ),
    )
  }
  for warning in prompt_warnings {
    warnings.push(warning)
  }
  let reasoning_effort = open_responses_v4_reasoning_effort_value(
    options.reasoning,
    warnings,
  )
  (warnings, reasoning_effort)
}

///|
fn encode_open_responses_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_options : OpenResponsesOptions,
  prompt : OpenResponsesV4PromptConversion,
  reasoning_effort : String?,
  stream : Bool,
) -> Json {
  let tools : Array[Json] = []
  for tool in options.tools {
    if open_responses_v4_tool_to_json(tool) is Some(value) {
      tools.push(value)
    }
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("input", Json::array(prompt.input)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if prompt.instructions is Some(value) {
        [("instructions", Json::string(value))]
      },
      ..if options.max_output_tokens is Some(value) {
        [("max_output_tokens", Json::number(value.to_double()))]
      },
      ..if options.temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if options.top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if options.frequency_penalty is Some(value) {
        [("frequency_penalty", Json::number(value))]
      },
      ..if options.presence_penalty is Some(value) {
        [("presence_penalty", Json::number(value))]
      },
      ..if open_responses_v4_reasoning(provider_options, reasoning_effort)
        is Some(value) {
        [("reasoning", value)]
      },
    ],
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
  }
  match options.tool_choice {
    Some(choice) =>
      fields["tool_choice"] = open_responses_v4_tool_choice_to_json(choice)
    None => ()
  }
  if open_responses_v4_text_format_to_json(options.response_format)
    is Some(text) {
    fields["text"] = text
  }
  Json::object(fields)
}

///|
/// Prepare a native V4 Open Responses request. The V4 model calls this path
/// directly; `ChatCallOptions` is not part of the request boundary.
fn prepare_open_responses_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
) -> OpenResponsesV4PreparedRequest raise {
  let parsed = parse_open_responses_provider_options(
    options.provider_options,
    provider_name,
  )
  let prompt = convert_v4_prompt_to_open_responses(options.prompt)
  let (warnings, reasoning_effort) = resolve_open_responses_v4_request_diagnostics(
    options,
    parsed,
    prompt.warnings,
  )
  {
    body: encode_open_responses_v4_request(
      model_id,
      options,
      parsed.options,
      prompt,
      reasoning_effort,
      stream,
    ),
    warnings,
  }
}

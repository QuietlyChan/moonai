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
  warnings~ : Array[@provider.Warning],
  extensions? : @protocol.OpenResponsesExtensionRegistry,
) -> Json {
  let tools : Array[Json] = []
  // Provider tools routed through an extension encode into their
  // namespaced wire type; the rest are dropped with a warning.
  let encoded_extensions : Map[String, String] = Map([])
  let encoded_extension_args : Map[String, Json] = Map([])
  let encoded_extension_choice_fns : Map[String, ((String, Json) -> Json?)?] = Map([],
  )
  for tool in options.tools {
    match tool {
      @provider.V4ProviderTool(value) => {
        let extension = match extensions {
          Some(registry) => registry.provider_tool_extension(value.id)
          None => None
        }
        match extension {
          Some(extension) =>
            match extension.encode_tool {
              Some(encode_tool) =>
                match encode_tool(value.name, value.args) {
                  Some(fields) => {
                    match fields {
                      Object(map) => {
                        let encoded : Map[String, Json] = Map([])
                        for entry in map.iter2() {
                          encoded[entry.0] = entry.1
                        }
                        encoded["type"] = Json::string(
                          extension.tool_type.unwrap(),
                        )
                        tools.push(Json::object(encoded))
                      }
                      _ => tools.push({ "type": extension.tool_type.unwrap() })
                    }
                    encoded_extensions[value.name] = extension.tool_type.unwrap()
                    encoded_extension_args[value.name] = value.args
                    encoded_extension_choice_fns[value.name] = extension.encode_tool_choice
                  }
                  None =>
                    warnings.push(
                      @provider.Warning::Unsupported(
                        feature="provider-defined tool \{value.id}",
                        details="The Open Responses extension could not encode the tool arguments.",
                      ),
                    )
                }
              None =>
                warnings.push(
                  @provider.Warning::Unsupported(
                    feature="provider-defined tool \{value.id}",
                    details="The Open Responses extension has no tool encoder.",
                  ),
                )
            }
          None =>
            warnings.push(
              @provider.Warning::Unsupported(
                feature="provider-defined tool \{value.id}",
                details="No Open Responses extension is registered for this tool.",
              ),
            )
        }
      }
      other =>
        if open_responses_v4_tool_to_json(other) is Some(value) {
          tools.push(value)
        }
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
    Some(@provider.V4ToolChoiceTool(name)) if encoded_extensions.contains(name) => {
      let tool_type = encoded_extensions.get(name).unwrap()
      let encoded_choice : Map[String, Json] = Map([])
      match encoded_extension_choice_fns.get(name) {
        Some(Some(encode_choice)) =>
          match encode_choice(name, encoded_extension_args.get(name).unwrap()) {
            Some(choice_fields) =>
              match choice_fields {
                Object(map) =>
                  for entry in map.iter2() {
                    encoded_choice[entry.0] = entry.1
                  }
                _ => ()
              }
            None =>
              warnings.push(
                @provider.Warning::Unsupported(
                  feature="tool choice for an Open Responses extension tool",
                  details="The extension could not encode the tool choice.",
                ),
              )
          }
        _ => ()
      }
      encoded_choice["type"] = Json::string(tool_type)
      fields["tool_choice"] = Json::object(encoded_choice)
    }
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
  extensions? : @protocol.OpenResponsesExtensionRegistry,
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
      warnings~,
      extensions?,
    ),
    warnings,
  }
}

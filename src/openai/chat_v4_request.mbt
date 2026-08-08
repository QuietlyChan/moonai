///|
fn openai_v4_reasoning_effort(
  effort : @provider.LanguageModelV4ReasoningEffort,
) -> String? {
  match effort {
    @provider.V4ReasoningProviderDefault => None
    @provider.V4ReasoningNone => Some("none")
    @provider.V4ReasoningMinimal => Some("minimal")
    @provider.V4ReasoningLow => Some("low")
    @provider.V4ReasoningMedium => Some("medium")
    @provider.V4ReasoningHigh => Some("high")
    @provider.V4ReasoningXHigh => Some("xhigh")
  }
}

///|
fn openai_v4_chat_tool(tool : @provider.LanguageModelV4Tool) -> Json? {
  match tool {
    @provider.V4FunctionTool(value) =>
      Some(
        Json::object(
          Map([
            ("type", Json::string("function")),
            (
              "function",
              Json::object(
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
              ),
            ),
          ]),
        ),
      )
    @provider.V4ProviderTool(_) => None
  }
}

///|
fn openai_v4_chat_tool_choice(
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
fn openai_v4_chat_response_format(
  format : @provider.LanguageModelV4ResponseFormat,
  strict_json_schema : Bool,
) -> Json? {
  match format {
    @provider.V4ResponseText => None
    @provider.V4ResponseJson(config) =>
      match config.schema {
        None => Some(({ "type": "json_object" } : Json))
        Some(schema) => {
          let json_schema : Map[String, Json] = Map([
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(strict_json_schema)),
          ])
          if config.description is Some(value) {
            json_schema["description"] = Json::string(value)
          }
          Some({
            "type": "json_schema",
            "json_schema": Json::object(json_schema),
          })
        }
      }
  }
}

///|
fn prepare_openai_v4_chat_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
  include_usage : Bool,
) -> OpenAIPreparedChatRequest raise {
  let parsed = parse_openai_chat_provider_options(
    options.provider_options,
    provider_name,
  )
  let provider_options = parsed.options
  let warnings = parsed.warnings.copy()
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="OpenAI Chat Completions does not support topK.",
      ),
    )
  }
  let capabilities = get_openai_language_model_capabilities(model_id)
  let is_reasoning_model = provider_options.force_reasoning.unwrap_or(
    capabilities.is_reasoning_model,
  )
  let reasoning_effort = match provider_options.reasoning_effort {
    Some(value) => Some(value)
    None => openai_v4_reasoning_effort(options.reasoning)
  }
  let system_message_mode = provider_options.system_message_mode.unwrap_or(
    if is_reasoning_model {
      "developer"
    } else {
      capabilities.system_message_mode
    },
  )
  let prompt = convert_v4_prompt_to_openai_chat(
    options.prompt,
    system_message_mode,
  )
  for warning in prompt.warnings {
    warnings.push(warning)
  }
  let tools : Array[Json] = []
  for tool in options.tools {
    match openai_v4_chat_tool(tool) {
      Some(value) => tools.push(value)
      None =>
        warnings.push(
          @provider.Warning::Unsupported(
            feature="tool type: provider",
            details="Provider-defined tools require the OpenAI Responses API.",
          ),
        )
    }
  }
  let mut max_tokens = options.max_output_tokens
  let mut max_completion_tokens = provider_options.max_completion_tokens
  let mut temperature = options.temperature
  let mut top_p = options.top_p
  let mut frequency_penalty = options.frequency_penalty
  let mut presence_penalty = options.presence_penalty
  let mut logit_bias = provider_options.logit_bias
  let mut logprobs = provider_options.logprobs
  let mut top_logprobs = provider_options.top_logprobs
  if is_reasoning_model {
    let allows_sampling = reasoning_effort == Some("none") &&
      capabilities.supports_non_reasoning_parameters
    if !allows_sampling {
      if temperature is Some(_) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="temperature",
            details="temperature is not supported for reasoning models.",
          ),
        )
        temperature = None
      }
      if top_p is Some(_) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="topP",
            details="topP is not supported for reasoning models.",
          ),
        )
        top_p = None
      }
      if logprobs {
        warnings.push(
          @provider.Warning::Other(
            message="logprobs is not supported for reasoning models",
          ),
        )
        logprobs = false
        top_logprobs = None
      }
    }
    if frequency_penalty is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="frequencyPenalty",
          details="frequencyPenalty is not supported for reasoning models.",
        ),
      )
      frequency_penalty = None
    }
    if presence_penalty is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="presencePenalty",
          details="presencePenalty is not supported for reasoning models.",
        ),
      )
      presence_penalty = None
    }
    if logit_bias is Some(_) {
      warnings.push(
        @provider.Warning::Other(
          message="logitBias is not supported for reasoning models",
        ),
      )
      logit_bias = None
    }
    if max_tokens is Some(value) {
      if max_completion_tokens is None {
        max_completion_tokens = Some(value)
      }
      max_tokens = None
    }
  } else if model_id.has_prefix("gpt-4o-search-preview") ||
    model_id.has_prefix("gpt-4o-mini-search-preview") {
    if temperature is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="temperature",
          details="temperature is not supported for search preview models.",
        ),
      )
      temperature = None
    }
  }
  let mut service_tier = provider_options.service_tier
  if service_tier == Some("flex") && !capabilities.supports_flex_processing {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="serviceTier",
        details="flex processing is not supported by this model.",
      ),
    )
    service_tier = None
  }
  if service_tier == Some("priority") &&
    !capabilities.supports_priority_processing {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="serviceTier",
        details="priority processing is not supported by this model.",
      ),
    )
    service_tier = None
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("messages", Json::array(prompt.messages)),
      ..if stream {
        [
          ("stream", Json::boolean(true)),
          ..if include_usage {
            [("stream_options", ({ "include_usage": true } : Json))]
          },
        ]
      },
      ..if logit_bias is Some(value) {
        [("logit_bias", value)]
      },
      ..if logprobs {
        [("logprobs", Json::boolean(true))]
      },
      ..if top_logprobs is Some(value) {
        [("top_logprobs", Json::number(value.to_double()))]
      },
      ..if provider_options.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if provider_options.parallel_tool_calls is Some(value) {
        [("parallel_tool_calls", Json::boolean(value))]
      },
      ..if max_tokens is Some(value) {
        [("max_tokens", Json::number(value.to_double()))]
      },
      ..if max_completion_tokens is Some(value) {
        [("max_completion_tokens", Json::number(value.to_double()))]
      },
      ..if temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if frequency_penalty is Some(value) {
        [("frequency_penalty", Json::number(value))]
      },
      ..if presence_penalty is Some(value) {
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
      ..if openai_v4_chat_response_format(
          options.response_format,
          provider_options.strict_json_schema,
        )
        is Some(value) {
        [("response_format", value)]
      },
      ..if provider_options.text_verbosity is Some(value) {
        [("verbosity", Json::string(value))]
      },
      ..if provider_options.store is Some(value) {
        [("store", Json::boolean(value))]
      },
      ..if provider_options.metadata is Some(value) {
        [("metadata", value)]
      },
      ..if provider_options.prediction is Some(value) {
        [("prediction", value)]
      },
      ..if reasoning_effort is Some(value) {
        [("reasoning_effort", Json::string(value))]
      },
      ..if service_tier is Some(value) {
        [("service_tier", Json::string(value))]
      },
      ..if provider_options.prompt_cache_key is Some(value) {
        [("prompt_cache_key", Json::string(value))]
      },
      ..if provider_options.prompt_cache_options is Some(value) {
        [("prompt_cache_options", value)]
      },
      ..if provider_options.prompt_cache_retention is Some(value) {
        [("prompt_cache_retention", Json::string(value))]
      },
      ..if provider_options.safety_identifier is Some(value) {
        [("safety_identifier", Json::string(value))]
      },
    ],
  )
  if options.tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    if options.tool_choice is Some(choice) {
      fields["tool_choice"] = openai_v4_chat_tool_choice(choice)
    }
  }
  { body: Json::object(fields), warnings }
}

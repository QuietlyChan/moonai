///|
fn openai_v4_responses_text_config(
  response_format : @provider.LanguageModelV4ResponseFormat,
  strict_json_schema : Bool,
  verbosity : String?,
) -> Json? {
  let fields : Map[String, Json] = Map([])
  match response_format {
    @provider.V4ResponseText => ()
    @provider.V4ResponseJson(config) =>
      match config.schema {
        None => fields["format"] = { "type": "json_object" }
        Some(schema) => {
          let format : Map[String, Json] = Map([
            ("type", Json::string("json_schema")),
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(strict_json_schema)),
          ])
          if config.description is Some(value) {
            format["description"] = Json::string(value)
          }
          fields["format"] = Json::object(format)
        }
      }
  }
  if verbosity is Some(value) {
    fields["verbosity"] = Json::string(value)
  }
  if fields.length() > 0 {
    Some(Json::object(fields))
  } else {
    None
  }
}

///|
fn resolve_openai_v4_responses_tool_choice(
  allowed_tools : Json?,
  choice : @provider.LanguageModelV4ToolChoice?,
  tools : Array[@provider.LanguageModelV4Tool],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Json? {
  match allowed_tools {
    Some(value) =>
      match openai_allowed_tools_choice(value, tool_name_mapping) {
        Some(resolved) => Some(resolved)
        None =>
          match choice {
            Some(resolved) =>
              Some(
                openai_v4_responses_tool_choice(
                  resolved, tools, tool_name_mapping,
                ),
              )
            None => None
          }
      }
    None =>
      match choice {
        Some(resolved) =>
          Some(
            openai_v4_responses_tool_choice(resolved, tools, tool_name_mapping),
          )
        None => None
      }
  }
}

///|
/// Prepare an OpenAI Responses request directly from the provider V4 contract.
fn prepare_openai_v4_responses_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
) -> OpenAIPreparedResponsesRequest raise {
  let parsed = parse_openai_responses_provider_options(
    options.provider_options,
    provider_name,
  )
  let provider_options = parsed.options
  let warnings = parsed.warnings.copy()
  let tool_name_mapping = create_openai_v4_tool_name_mapping(options.tools)
  let tool_capabilities = openai_responses_v4_tool_capabilities(options.tools)
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="OpenAI Responses does not support topK.",
      ),
    )
  }
  let capabilities = get_openai_language_model_capabilities(model_id)
  if options.stop_sequences.length() > 0 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="stopSequences",
        details="OpenAI Responses does not support stop sequences.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="OpenAI Responses does not support seed.",
      ),
    )
  }
  if options.presence_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="presencePenalty",
        details="OpenAI Responses does not support presencePenalty.",
      ),
    )
  }
  if options.frequency_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="frequencyPenalty",
        details="OpenAI Responses does not support frequencyPenalty.",
      ),
    )
  }
  if provider_options.conversation is Some(_) &&
    provider_options.previous_response_id is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="conversation",
        details="conversation and previousResponseId cannot be used together.",
      ),
    )
  }
  let is_reasoning_model = provider_options.force_reasoning.unwrap_or(
    capabilities.is_reasoning_model,
  )
  let resolved_effort = match provider_options.reasoning_effort {
    Some(value) => Some(value)
    None => openai_v4_reasoning_effort(options.reasoning)
  }
  let resolved_summary = match provider_options.reasoning_summary {
    Some(value) => Some(value)
    None if resolved_effort is Some(value) && value != "none" =>
      Some("detailed")
    None => None
  }
  let system_message_mode = provider_options.system_message_mode.unwrap_or(
    if is_reasoning_model {
      "developer"
    } else {
      capabilities.system_message_mode
    },
  )
  let input = convert_v4_prompt_to_openai_responses(
    options.prompt,
    system_message_mode,
    provider_options.pass_through_unsupported_files,
    provider_name,
    provider_options.store.unwrap_or(true),
    provider_options.conversation is Some(_),
    provider_options.previous_response_id is Some(_),
    warnings,
    tool_name_mapping,
    tool_capabilities,
  )
  let tools = prepare_openai_v4_responses_tools(options.tools, warnings)
  let mut temperature = options.temperature
  let mut top_p = options.top_p
  if is_reasoning_model {
    let allows_sampling = resolved_effort == Some("none") &&
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
    }
  } else {
    if provider_options.reasoning_effort is Some(_) ||
      !(options.reasoning is @provider.V4ReasoningProviderDefault) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningEffort",
          details="reasoningEffort is not supported for non-reasoning models.",
        ),
      )
    }
    if provider_options.reasoning_summary is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningSummary",
          details="reasoningSummary is not supported for non-reasoning models.",
        ),
      )
    }
    if provider_options.reasoning_mode is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningMode",
          details="reasoningMode is not supported for non-reasoning models.",
        ),
      )
    }
    if provider_options.reasoning_context is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningContext",
          details="reasoningContext is not supported for non-reasoning models.",
        ),
      )
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
  let include_values = provider_options.include_values.copy()
  if provider_options.top_logprobs is Some(_) {
    append_openai_include(include_values, "message.output_text.logprobs")
  }
  if provider_options.store == Some(false) && is_reasoning_model {
    append_openai_include(include_values, "reasoning.encrypted_content")
  }
  let mut web_search_tool_name : String? = None
  for tool in options.tools {
    match tool {
      @provider.V4ProviderTool(value) if value.id == "openai.web_search" ||
        value.id == "openai.web_search_preview" => {
        if web_search_tool_name is None {
          web_search_tool_name = Some(value.name)
        }
        append_openai_include(include_values, "web_search_call.action.sources")
      }
      @provider.V4ProviderTool(value) if value.id == "openai.code_interpreter" =>
        append_openai_include(include_values, "code_interpreter_call.outputs")
      _ => ()
    }
  }
  let reasoning : Map[String, Json] = Map([])
  if is_reasoning_model {
    if resolved_effort is Some(value) {
      reasoning["effort"] = Json::string(value)
    }
    if resolved_summary is Some(value) {
      reasoning["summary"] = Json::string(value)
    }
    if provider_options.reasoning_mode is Some(value) {
      reasoning["mode"] = Json::string(value)
    }
    if provider_options.reasoning_context is Some(value) {
      reasoning["context"] = Json::string(value)
    }
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("input", Json::array(input)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if options.max_output_tokens is Some(value) {
        [("max_output_tokens", Json::number(value.to_double()))]
      },
      ..if temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if openai_v4_responses_text_config(
          options.response_format,
          provider_options.strict_json_schema,
          provider_options.text_verbosity,
        )
        is Some(value) {
        [("text", value)]
      },
      ..if provider_options.conversation is Some(value) {
        [("conversation", Json::string(value))]
      },
      ..if provider_options.max_tool_calls is Some(value) {
        [("max_tool_calls", Json::number(value.to_double()))]
      },
      ..if provider_options.metadata is Some(value) {
        [("metadata", value)]
      },
      ..if provider_options.parallel_tool_calls is Some(value) {
        [("parallel_tool_calls", Json::boolean(value))]
      },
      ..if provider_options.previous_response_id is Some(value) {
        [("previous_response_id", Json::string(value))]
      },
      ..if provider_options.store is Some(value) {
        [("store", Json::boolean(value))]
      },
      ..if provider_options.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if provider_options.instructions is Some(value) {
        [("instructions", Json::string(value))]
      },
      ..if service_tier is Some(value) {
        [("service_tier", Json::string(value))]
      },
      ..if include_values.length() > 0 {
        [
          (
            "include",
            Json::array([ for value in include_values => Json::string(value) ]),
          ),
        ]
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
      ..if provider_options.top_logprobs is Some(value) {
        [("top_logprobs", Json::number(value.to_double()))]
      },
      ..if provider_options.truncation is Some(value) {
        [("truncation", Json::string(value))]
      },
      ..if openai_context_management(provider_options.context_management)
        is Some(value) {
        [("context_management", value)]
      },
      ..if reasoning.length() > 0 {
        [("reasoning", Json::object(reasoning))]
      },
    ],
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    if resolve_openai_v4_responses_tool_choice(
        provider_options.allowed_tools,
        options.tool_choice,
        options.tools,
        tool_name_mapping,
      )
      is Some(choice) {
      fields["tool_choice"] = choice
    }
  }
  {
    body: Json::object(fields),
    warnings,
    tool_name_mapping,
    shell_provider_executed: openai_responses_v4_shell_provider_executed(
      options.tools,
    ),
    web_search_tool_name,
  }
}

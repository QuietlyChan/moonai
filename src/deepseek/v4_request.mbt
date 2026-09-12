///|
priv struct PreparedDeepSeekRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn deepseek_v4_tool_json(tool : @provider.LanguageModelV4Tool) -> Json? {
  match tool {
    @provider.V4FunctionTool(value) => {
      let function : Map[String, Json] = Map([
        ("name", Json::string(value.name)),
      ])
      if value.description is Some(description) {
        function["description"] = Json::string(description)
      }
      function["parameters"] = value.input_schema
      if value.strict is Some(strict) {
        function["strict"] = Json::boolean(strict)
      }
      Some({ "type": "function", "function": Json::object(function) })
    }
    @provider.V4ProviderTool(_) => None
  }
}

///|
fn deepseek_v4_tool_choice(
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
fn deepseek_v4_reasoning_effort(
  effort : @provider.LanguageModelV4ReasoningEffort,
  warnings : Array[@provider.Warning],
) -> String? {
  match effort {
    @provider.V4ReasoningProviderDefault | @provider.V4ReasoningNone => None
    _ =>
      @provider_utils.map_reasoning_to_provider_effort(
        effort.to_reasoning_effort(),
        {
          "minimal": "low",
          "low": "low",
          "medium": "medium",
          "high": "high",
          "xhigh": "max",
        },
        warnings,
      )
  }
}

///|
/// DeepSeek publishes V4 models under versioned ids and unversioned
/// aliases (`deepseek-flash`, `deepseek-pro`); only the legacy
/// `deepseek-chat` / `deepseek-reasoner` ids predate V4.
fn is_deepseek_v4_model(model_id : String) -> Bool {
  model_id.contains("deepseek-v4") ||
  model_id.has_prefix("deepseek-flash") ||
  model_id.has_prefix("deepseek-pro")
}

///|
fn prepare_deepseek_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
  supports_thinking : Bool,
  supports_structured_outputs : Bool,
  supports_strict_tool_calls : Bool,
) -> PreparedDeepSeekRequest raise {
  let parsed = parse_deepseek_options(options.provider_options, provider_name)
  let warnings = parsed.warnings.copy()
  let prompt = convert_v4_prompt_to_deepseek(
    options.prompt,
    options.response_format,
    model_id,
    supports_structured_outputs,
  )
  for warning in prompt.warnings {
    warnings.push(warning)
  }
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="DeepSeek Chat does not support topK.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="DeepSeek does not support deterministic seed control.",
      ),
    )
  }
  let tools : Array[Json] = []
  for tool in options.tools {
    match deepseek_v4_tool_json(tool) {
      Some(value) => tools.push(value)
      None => {
        let feature = match tool {
          @provider.V4ProviderTool(value) => "provider-defined tool \{value.id}"
          _ => "provider-defined tool"
        }
        warnings.push(
          @provider.Warning::Unsupported(
            feature~,
            details="DeepSeek Chat accepts function tools only.",
          ),
        )
      }
    }
  }
  let has_strict_tool = options.tools
    .iter()
    .any(fn(tool) {
      match tool {
        @provider.V4FunctionTool(value) => value.strict == Some(true)
        _ => false
      }
    })
  guard !(has_strict_tool && !supports_strict_tool_calls) else {
    raise @provider.UnsupportedFunctionalityError(
      functionality="DeepSeek strict tool calls",
    )
  }
  guard !(has_strict_tool &&
    options.tools
    .iter()
    .any(fn(tool) {
      match tool {
        @provider.V4FunctionTool(value) => value.strict != Some(true)
        _ => false
      }
    })) else {
    raise @provider.UnsupportedFunctionalityError(
      functionality="mixed DeepSeek strict and non-strict tool calls",
    )
  }
  let thinking_type = if !supports_thinking {
    None
  } else {
    match parsed.options.thinking_type {
      Some(value) => Some(value)
      None =>
        match options.reasoning {
          @provider.V4ReasoningNone => Some("disabled")
          @provider.V4ReasoningProviderDefault => None
          _ => Some("enabled")
        }
    }
  }
  let reasoning_effort = match parsed.options.reasoning_effort {
    Some(value) => Some(value)
    None => deepseek_v4_reasoning_effort(options.reasoning, warnings)
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(model_id)),
    ("messages", Json::array(prompt.messages)),
  ])
  if stream {
    fields["stream"] = Json::boolean(true)
    fields["stream_options"] = { "include_usage": true }
  }
  if options.max_output_tokens is Some(value) {
    fields["max_tokens"] = Json::number(value.to_double())
  }
  // DeepSeek thinking mode (default on V4 models) ignores sampling
  // controls; deprecated penalties are omitted with a warning.
  let is_thinking_enabled = supports_thinking &&
    thinking_type != Some("disabled") &&
    (
      thinking_type is Some(_) ||
      model_id == "deepseek-reasoner" ||
      is_deepseek_v4_model(model_id)
    )
  if options.temperature is Some(value) {
    if is_thinking_enabled {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="temperature",
          details="temperature has no effect when DeepSeek thinking is enabled. Set providerOptions.deepseek.thinking_type to 'disabled' to use temperature.",
        ),
      )
    } else {
      fields["temperature"] = Json::number(value)
    }
  }
  if options.top_p is Some(value) {
    if is_thinking_enabled {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="topP",
          details="topP has no effect when DeepSeek thinking is enabled. Set providerOptions.deepseek.thinking_type to 'disabled' to use topP.",
        ),
      )
    } else {
      fields["top_p"] = Json::number(value)
    }
  }
  if options.frequency_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Deprecated(
        setting="frequencyPenalty",
        message="frequencyPenalty is deprecated by DeepSeek and has been omitted. Remove frequencyPenalty from the request.",
      ),
    )
  }
  if options.presence_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Deprecated(
        setting="presencePenalty",
        message="presencePenalty is deprecated by DeepSeek and has been omitted. Remove presencePenalty from the request.",
      ),
    )
  }
  if options.stop_sequences.length() > 0 {
    fields["stop"] = Json::array(
      [
        for value in options.stop_sequences => Json::string(value)
      ],
    )
  }
  // Request log probabilities when explicitly enabled or a top-logprobs
  // count is given (AI SDK #19407).
  if parsed.options.logprobs == Some(true) || parsed.options.top_logprobs is Some(_) {
    fields["logprobs"] = Json::boolean(true)
  }
  match parsed.options.top_logprobs {
    Some(count) => fields["top_logprobs"] = Json::number(count.to_double())
    None => ()
  }
  match options.response_format {
    @provider.V4ResponseJson(config) =>
      match config.schema {
        Some(schema) if supports_structured_outputs => {
          let json_schema : Map[String, Json] = Map([
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(parsed.options.strict_json_schema)),
          ])
          if config.description is Some(value) {
            json_schema["description"] = Json::string(value)
          }
          fields["response_format"] = {
            "type": "json_schema",
            "json_schema": Json::object(json_schema),
          }
        }
        _ => fields["response_format"] = { "type": "json_object" }
      }
    @provider.V4ResponseText => ()
  }
  if options.tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    if options.tool_choice is Some(choice) {
      fields["tool_choice"] = deepseek_v4_tool_choice(choice)
    }
  }
  if thinking_type is Some(value) {
    fields["thinking"] = { "type": value }
  }
  if thinking_type != Some("disabled") && reasoning_effort is Some(value) {
    fields["reasoning_effort"] = Json::string(value)
  }
  { body: Json::object(fields), warnings, }
}

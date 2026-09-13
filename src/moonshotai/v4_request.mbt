///|
priv struct PreparedMoonshotRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
/// Kimi K3 maps normalized reasoning levels onto three efforts.
fn moonshot_k3_effort_map() -> Map[String, String] {
  {
    "minimal": "low",
    "low": "low",
    "medium": "high",
    "high": "high",
    "xhigh": "max",
  }
}

///|
/// Kimi K3 always reasons and never accepts the `thinking` field; a
/// requested effort wins over the normalized reasoning level.
fn moonshot_k3_reasoning(
  requested~ : String?,
  reasoning~ : @provider.LanguageModelV4ReasoningEffort,
  thinking_requested~ : Bool,
  warnings~ : Array[@provider.Warning],
) -> String? {
  if thinking_requested {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="thinking",
        details="Kimi K3 always reasons and does not accept the thinking field. The option has been omitted.",
      ),
    )
  }
  match reasoning {
    @provider.V4ReasoningNone =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoning \"none\"",
          details="Kimi K3 reasoning cannot be disabled.",
        ),
      )
    _ => ()
  }
  match requested {
    Some(value) => Some(value)
    None =>
      @provider_utils.map_reasoning_to_provider_effort(
        reasoning.to_reasoning_effort(),
        moonshot_k3_effort_map(),
        warnings,
      )
  }
}

///|
/// Thinking and reasoning-effort settings for the request, resolved per
/// model family.
priv struct MoonshotReasoningPlan {
  thinking : Json?
  reasoning_effort : String?
}

///|
fn moonshot_reasoning_plan(
  family~ : MoonshotAIModelFamily,
  model_id~ : String,
  requested_thinking~ : String?,
  budget_tokens~ : Int?,
  requested_effort~ : String?,
  reasoning_history_preserved~ : Bool,
  reasoning~ : @provider.LanguageModelV4ReasoningEffort,
  warnings~ : Array[@provider.Warning],
) -> MoonshotReasoningPlan {
  if budget_tokens is Some(_) {
    warnings.push(
      @provider.Warning::Deprecated(
        setting="providerOptions.moonshotai.thinking.budgetTokens",
        message="Moonshot Chat Completions does not support budget_tokens. Remove budgetTokens; the option has been omitted.",
      ),
    )
  }
  let warn_unsupported_effort = fn() -> Unit {
    if requested_effort is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningEffort",
          details="reasoningEffort is only supported by Kimi K3 and has been omitted for model \"\{model_id}\".",
        ),
      )
    }
  }
  let thinking_type : String? = match requested_thinking {
    Some(value) => Some(value)
    None =>
      match reasoning {
        @provider.V4ReasoningNone => Some("disabled")
        @provider.V4ReasoningProviderDefault => None
        _ => Some("enabled")
      }
  }
  match family {
    KimiK3 => {
      let effort = moonshot_k3_reasoning(
        requested=requested_effort,
        reasoning~,
        thinking_requested=requested_thinking is Some(_),
        warnings~,
      )
      { thinking: None, reasoning_effort: effort, }
    }
    KimiK27 => {
      warn_unsupported_effort()
      if requested_thinking == Some("disabled") ||
        reasoning is @provider.V4ReasoningNone {
        warnings.push(
          @provider.Warning::Unsupported(
            feature=if requested_thinking == Some("disabled") {
              "thinking.type \"disabled\""
            } else {
              "reasoning \"none\""
            },
            details="Kimi K2.7 thinking cannot be disabled.",
          ),
        )
      }
      let thinking : Json? = if requested_thinking == Some("enabled") {
        let value : Json = { "type": "enabled" }
        Some(value)
      } else {
        None
      }
      { thinking, reasoning_effort: None, }
    }
    KimiK26 => {
      warn_unsupported_effort()
      let effective_type = match thinking_type {
        Some(value) => Some(value)
        None =>
          match reasoning {
            @provider.V4ReasoningNone => Some("disabled")
            @provider.V4ReasoningProviderDefault => None
            _ => Some("enabled")
          }
      }
      if effective_type is Some(_) || reasoning_history_preserved {
        let value = effective_type.unwrap_or("enabled")
        let fields : Map[String, Json] = Map([("type", Json::string(value))])
        if reasoning_history_preserved {
          fields["keep"] = Json::string("all")
        }
        { thinking: Some(Json::object(fields)), reasoning_effort: None, }
      } else {
        { thinking: None, reasoning_effort: None, }
      }
    }
    KimiK25 => {
      warn_unsupported_effort()
      let thinking : Json? = match thinking_type {
        Some(value) => {
          let typed : Json = { "type": value }
          Some(typed)
        }
        None => None
      }
      if reasoning_history_preserved {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="reasoningHistory 'preserved' is not supported by model \"\{model_id}\"",
            details="Moonshot AI preserves reasoning across Kimi K2.5 turns automatically; reasoningHistory has been ignored.",
          ),
        )
      }
      { thinking, reasoning_effort: None, }
    }
    MoonshotV1 => {
      warn_unsupported_effort()
      if requested_thinking is Some(_) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="thinking",
            details="thinking is not supported by model \"\{model_id}\" and has been omitted.",
          ),
        )
      }
      match reasoning {
        @provider.V4ReasoningProviderDefault | @provider.V4ReasoningNone => ()
        _ =>
          warnings.push(
            @provider.Warning::Unsupported(
              feature="reasoning",
              details="reasoning is not supported by model \"\{model_id}\".",
            ),
          )
      }
      if reasoning_history_preserved {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="reasoningHistory 'preserved' is not supported by model \"\{model_id}\"",
            details="Moonshot V1 models do not preserve reasoning; reasoningHistory has been ignored.",
          ),
        )
      }
      { thinking: None, reasoning_effort: None, }
    }
    Unknown => {
      if reasoning is @provider.V4ReasoningNone {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="reasoning \"none\"",
            details="Use providerOptions.moonshotai.thinking to control thinking on custom models.",
          ),
        )
      }
      let effort = match requested_effort {
        Some(value) => Some(value)
        None =>
          @provider_utils.map_reasoning_to_provider_effort(
            reasoning.to_reasoning_effort(),
            moonshot_k3_effort_map(),
            warnings,
          )
      }
      let thinking : Json? = match requested_thinking {
        Some(value) => {
          let typed : Json = { "type": value }
          Some(typed)
        }
        None => None
      }
      if reasoning_history_preserved {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="reasoningHistory 'preserved' is not supported by model \"\{model_id}\"",
            details="reasoningHistory has been ignored for this model.",
          ),
        )
      }
      { thinking, reasoning_effort: effort, }
    }
  }
}

///|
/// Build the Moonshot AI Chat Completions request body with warnings.
fn prepare_moonshot_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
  include_usage : Bool,
  supports_structured_outputs : Bool,
) -> PreparedMoonshotRequest raise {
  let parsed = parse_moonshot_options(options.provider_options, provider_name)
  let warnings = parsed.warnings.copy()
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="Moonshot AI does not support topK.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="Moonshot AI does not support deterministic seed control.",
      ),
    )
  }
  // Kimi models fix the sampling controls; omit them with a warning
  // instead of letting the API reject the request.
  let supports_sampling_options = !is_moonshot_ai_kimi_model(model_id)
  if !supports_sampling_options {
    if options.temperature is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="temperature",
          details="temperature is fixed by model \"\{model_id}\" and has been omitted.",
        ),
      )
    }
    if options.top_p is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="topP",
          details="topP is fixed by model \"\{model_id}\" and has been omitted.",
        ),
      )
    }
    if options.frequency_penalty is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="frequencyPenalty",
          details="frequencyPenalty is fixed by model \"\{model_id}\" and has been omitted.",
        ),
      )
    }
    if options.presence_penalty is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="presencePenalty",
          details="presencePenalty is fixed by model \"\{model_id}\" and has been omitted.",
        ),
      )
    }
  }
  let prepared_tools = prepare_moonshot_tools(
    tools=options.tools,
    tool_choice=options.tool_choice,
    model_id~,
  )
  for warning in prepared_tools.warnings {
    warnings.push(warning)
  }
  // Response format first so the message conversion can reject Partial
  // Mode combined with json_object.
  let response_format : Json? = match options.response_format {
    @provider.V4ResponseJson(config) =>
      match config.schema {
        Some(schema) if supports_structured_outputs => {
          let normalized = moonshot_schema_without_dollar_keyword(schema)
          let json_schema : Map[String, Json] = Map([
            ("name", Json::string(config.name.unwrap_or("response"))),
            (
              "strict",
              Json::boolean(parsed.options.strict_json_schema.unwrap_or(true)),
            ),
            ("schema", normalize_json_schema_for_mfjs(normalized)),
          ])
          Some({
            "type": "json_schema",
            "json_schema": Json::object(json_schema),
          })
        }
        _ => Some({ "type": "json_object" })
      }
    @provider.V4ResponseText => None
  }
  let prompt = convert_v4_prompt_to_moonshot(
    options.prompt,
    model_id~,
    provider_name~,
    response_format~,
  )
  for warning in prompt.warnings {
    warnings.push(warning)
  }
  let plan = moonshot_reasoning_plan(
    family=get_moonshot_ai_model_family(model_id),
    model_id~,
    requested_thinking=parsed.options.thinking_type,
    budget_tokens=parsed.options.thinking_budget_tokens,
    requested_effort=parsed.options.reasoning_effort,
    reasoning_history_preserved=parsed.options.reasoning_history ==
      Some("preserved"),
    reasoning=options.reasoning,
    warnings~,
  )
  let fields : Map[String, Json] = Map([
    ("model", Json::string(model_id)),
    ("messages", Json::array(prompt.messages)),
  ])
  // Moonshot AI uses the OpenAI completion-token field name natively
  // (AI SDK #19605).
  if options.max_output_tokens is Some(value) {
    fields["max_completion_tokens"] = Json::number(value.to_double())
  }
  if supports_sampling_options {
    if options.temperature is Some(value) {
      fields["temperature"] = Json::number(value)
    }
    if options.top_p is Some(value) {
      fields["top_p"] = Json::number(value)
    }
    if options.frequency_penalty is Some(value) {
      fields["frequency_penalty"] = Json::number(value)
    }
    if options.presence_penalty is Some(value) {
      fields["presence_penalty"] = Json::number(value)
    }
  }
  if parsed.options.logprobs == Some(true) ||
    parsed.options.top_logprobs is Some(_) {
    fields["logprobs"] = Json::boolean(true)
  }
  match parsed.options.top_logprobs {
    Some(count) => fields["top_logprobs"] = Json::number(count.to_double())
    None => ()
  }
  match response_format {
    Some(value) => fields["response_format"] = value
    None => ()
  }
  if options.stop_sequences.length() > 0 {
    fields["stop"] = Json::array(
      [
        for value in options.stop_sequences => Json::string(value)
      ],
    )
  }
  match prepared_tools.tools {
    Some(tools) => {
      fields["tools"] = Json::array(tools)
      match prepared_tools.tool_choice {
        Some(choice) => fields["tool_choice"] = choice
        None => ()
      }
    }
    None => ()
  }
  match parsed.options.prediction {
    Some(value) => fields["prediction"] = value
    None => ()
  }
  match plan.thinking {
    Some(value) => fields["thinking"] = value
    None => ()
  }
  match plan.reasoning_effort {
    Some(value) => fields["reasoning_effort"] = Json::string(value)
    None => ()
  }
  match parsed.options.prompt_cache_key {
    Some(value) => fields["prompt_cache_key"] = Json::string(value)
    None => ()
  }
  match parsed.options.safety_identifier {
    Some(value) => fields["safety_identifier"] = Json::string(value)
    None => ()
  }
  if stream {
    fields["stream"] = Json::boolean(true)
    if include_usage {
      fields["stream_options"] = { "include_usage": true }
    }
  }
  { body: Json::object(fields), warnings, }
}

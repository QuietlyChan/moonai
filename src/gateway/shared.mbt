///|
fn gateway_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn gateway_request_headers(
  api_key~ : String,
  headers~ : Map[String, String],
  extra~ : Map[String, String],
  model_id~ : String,
  streaming~ : Bool,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="AI_GATEWAY_API_KEY",
    description="AI Gateway",
  )
  let base : Map[String, String] = Map([
    ("Authorization", "Bearer \{api_key}"),
    ("Content-Type", "application/json"),
    ("ai-language-model-specification-version", "4"),
    ("ai-language-model-id", model_id),
    ("accept", if streaming { "text/event-stream" } else { "application/json" }),
  ])
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(base, headers),
      extra,
    ),
    ["ai-sdk/gateway/\{VERSION}"],
  )
}

///|
/// Map a V4 finish-reason JSON ({unified, raw}) onto the typed struct.
fn gateway_finish_reason(
  value : Json?,
) -> @provider.LanguageModelV4FinishReason {
  match value {
    Some(Object(fields)) => {
      let unified = match fields.get("unified") {
        Some(String(raw)) => gateway_unified_finish_reason(raw)
        _ => @provider.V4FinishOther
      }
      let raw = match fields.get("raw") {
        Some(String(text)) => Some(text)
        _ => None
      }
      { unified, raw, }
    }
    _ => { unified: @provider.V4FinishOther, raw: None, }
  }
}

///|
fn gateway_unified_finish_reason(
  raw : String,
) -> @provider.LanguageModelV4UnifiedFinishReason {
  match raw {
    "stop" => @provider.V4FinishStop
    "length" => @provider.V4FinishLength
    "content-filter" => @provider.V4FinishContentFilter
    "tool-calls" => @provider.V4FinishToolCalls
    "error" => @provider.V4FinishError
    _ => @provider.V4FinishOther
  }
}

///|
fn gateway_nested_int(value : Json?, outer~ : String, inner~ : String) -> Int? {
  match value {
    Some(Object(fields)) =>
      match fields.get(outer) {
        Some(Object(outer_fields)) =>
          match outer_fields.get(inner) {
            Some(Number(count, ..)) => Some(count.to_int())
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// Decode the V4 usage JSON ({inputTokens:{total,...},outputTokens:{...}}).
fn gateway_usage(value : Json?) -> @provider.LanguageModelV4Usage {
  let input_total = gateway_nested_int(
    value,
    outer="inputTokens",
    inner="total",
  )
  let input_cache_read = gateway_nested_int(
    value,
    outer="inputTokens",
    inner="cacheRead",
  )
  let output_total = gateway_nested_int(
    value,
    outer="outputTokens",
    inner="total",
  )
  let output_reasoning = gateway_nested_int(
    value,
    outer="outputTokens",
    inner="reasoning",
  )
  {
    input_tokens: {
      total: input_total,
      no_cache: match (input_total, input_cache_read) {
        (Some(total), Some(cache_read)) => Some(total - cache_read)
        _ => input_total
      },
      cache_read: input_cache_read,
      cache_write: None,
    },
    output_tokens: {
      total: output_total,
      text: match (output_total, output_reasoning) {
        (Some(total), Some(reasoning)) => Some(total - reasoning)
        _ => output_total
      },
      reasoning: output_reasoning,
    },
    raw: value,
  }
}

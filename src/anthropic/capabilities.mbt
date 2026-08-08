///|
/// Request-shaping capabilities for one Anthropic model family.
priv struct AnthropicModelCapabilities {
  max_output_tokens : Int
  supports_structured_output : Bool
  supports_adaptive_thinking : Bool
  rejects_sampling_parameters : Bool
  supports_xhigh_effort : Bool
  rejects_thinking_disabled_above_high : Bool
  is_known_model : Bool
}

///|
fn anthropic_capabilities(
  max_output_tokens : Int,
  supports_structured_output : Bool,
  supports_adaptive_thinking : Bool,
  rejects_sampling_parameters : Bool,
  supports_xhigh_effort : Bool,
  rejects_thinking_disabled_above_high : Bool,
  is_known_model : Bool,
) -> AnthropicModelCapabilities {
  {
    max_output_tokens,
    supports_structured_output,
    supports_adaptive_thinking,
    rejects_sampling_parameters,
    supports_xhigh_effort,
    rejects_thinking_disabled_above_high,
    is_known_model,
  }
}

///|
/// Match legacy Claude families without treating future version prefixes such
/// as `claude-30`, `claude-v20`, or `claude-instantaneous` as legacy models.
fn is_legacy_anthropic_model(model_id : String) -> Bool {
  let parts = model_id.split("claude-").to_array()
  for index = 1; index < parts.length(); index = index + 1 {
    let suffix = parts[index]
    if suffix == "instant" ||
      suffix.has_prefix("instant-") ||
      suffix == "2" ||
      suffix.has_prefix("2-") ||
      suffix.has_prefix("2.") ||
      suffix.has_prefix("2:") ||
      suffix == "v2" ||
      suffix.has_prefix("v2-") ||
      suffix.has_prefix("v2.") ||
      suffix.has_prefix("v2:") ||
      suffix == "3" ||
      suffix.has_prefix("3-") ||
      suffix.has_prefix("3.") {
      return true
    }
  }
  false
}

///|
/// Resolve the same model-family defaults used by the TypeScript Anthropic
/// provider. Unknown non-Claude endpoints keep conservative limits, while
/// future Claude families inherit the newest known capability envelope.
fn get_anthropic_model_capabilities(
  model_id : String,
) -> AnthropicModelCapabilities {
  if model_id.contains("claude-opus-5") {
    anthropic_capabilities(128000, true, true, true, true, true, true)
  } else if model_id.contains("claude-opus-4-8") ||
    model_id.contains("claude-opus-4-7") ||
    model_id.contains("claude-fable-5") ||
    model_id.contains("claude-sonnet-5") {
    anthropic_capabilities(128000, true, true, true, true, false, true)
  } else if model_id.contains("claude-sonnet-4-6") ||
    model_id.contains("claude-opus-4-6") {
    anthropic_capabilities(128000, true, true, false, false, false, true)
  } else if model_id.contains("claude-sonnet-4-5") ||
    model_id.contains("claude-opus-4-5") ||
    model_id.contains("claude-haiku-4-5") {
    anthropic_capabilities(64000, true, false, false, false, false, true)
  } else if model_id.contains("claude-opus-4-1") {
    anthropic_capabilities(32000, true, false, false, false, false, true)
  } else if model_id.contains("claude-sonnet-4-") {
    anthropic_capabilities(64000, false, false, false, false, false, true)
  } else if model_id.contains("claude-opus-4-") {
    anthropic_capabilities(32000, false, false, false, false, false, true)
  } else if model_id.contains("claude-3-haiku") {
    anthropic_capabilities(4096, false, false, false, false, false, true)
  } else if is_legacy_anthropic_model(model_id) {
    anthropic_capabilities(4096, false, false, false, false, false, false)
  } else if model_id.contains("claude-") {
    anthropic_capabilities(128000, true, true, true, true, true, false)
  } else {
    anthropic_capabilities(4096, false, false, false, false, false, false)
  }
}

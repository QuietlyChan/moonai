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
  } else if model_id.contains("claude-instant") ||
    model_id.contains("claude-v2") ||
    model_id.contains("claude-2") ||
    model_id.contains("claude-3") {
    anthropic_capabilities(4096, false, false, false, false, false, false)
  } else if model_id.contains("claude-") {
    anthropic_capabilities(128000, true, true, true, true, true, false)
  } else {
    anthropic_capabilities(4096, false, false, false, false, false, false)
  }
}

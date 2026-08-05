///|
/// Convert Alibaba's OpenAI-compatible token accounting into the shared usage
/// contract, including prompt-cache and reasoning token details.
pub fn convert_alibaba_chat_usage(json : Json) -> @provider.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
  let output_tokens = @provider_utils.json_int_field(json, "completion_tokens")
  let reasoning_tokens = match json {
    {
      "completion_tokens_details": { "reasoning_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  let cached_input_tokens = match json {
    { "prompt_tokens_details": { "cached_tokens": Number(value, ..), .. }, .. } =>
      value.to_int()
    _ => 0
  }
  let cache_write_input_tokens = match json {
    {
      "prompt_tokens_details": {
        "cache_creation_input_tokens": Number(value, ..),
        ..
      },
      ..
    } => value.to_int()
    _ => 0
  }
  {
    input_tokens,
    output_tokens,
    total_tokens: @provider_utils.json_int_field(
      json,
      "total_tokens",
      default=input_tokens + output_tokens,
    ),
    reasoning_tokens,
    cached_input_tokens,
    cache_write_input_tokens,
  }
}

///|
/// Convert Alibaba's native embedding usage object.
fn convert_alibaba_embedding_usage(json : Json) -> @provider.Usage {
  let total = @provider_utils.json_int_field(json, "total_tokens")
  {
    input_tokens: total,
    output_tokens: 0,
    total_tokens: total,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
}

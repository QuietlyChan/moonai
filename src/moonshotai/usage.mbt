///|
/// Convert Moonshot AI token accounting to the provider-neutral V4 shape.
///
/// Moonshot can report cache hits either as top-level `cached_tokens` or in
/// OpenAI-compatible `prompt_tokens_details`; the native field wins.
pub fn convert_moonshotai_chat_usage(
  usage : Json?,
) -> @provider.LanguageModelV4Usage {
  match usage {
    Some(json) if !(json is Null) => {
      let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
      let output_tokens = @provider_utils.json_int_field(
        json, "completion_tokens",
      )
      let cache_read = match json {
        { "cached_tokens": Number(value, ..), .. } => value.to_int()
        {
          "prompt_tokens_details": { "cached_tokens": Number(value, ..), .. },
          ..
        } => value.to_int()
        _ => 0
      }
      let reasoning = match json {
        {
          "completion_tokens_details": {
            "reasoning_tokens": Number(value, ..),
            ..
          },
          ..
        } => value.to_int()
        _ => 0
      }
      {
        input_tokens: {
          total: Some(input_tokens),
          no_cache: Some(input_tokens - cache_read),
          cache_read: Some(cache_read),
          cache_write: None,
        },
        output_tokens: {
          total: Some(output_tokens),
          text: Some(output_tokens - reasoning),
          reasoning: Some(reasoning),
        },
        raw: Some(json),
      }
    }
    _ => @provider.LanguageModelV4Usage::unknown()
  }
}

///|
/// AI SDK-style camel-case alias.
pub fn convertMoonshotAIChatUsage(
  usage : Json?,
) -> @provider.LanguageModelV4Usage {
  convert_moonshotai_chat_usage(usage)
}

///|
/// Create a V4 usage value for a provider response without token accounting.
/// Missing counters remain absent so callers can distinguish unavailable
/// telemetry from measured zero usage.
pub fn create_null_language_model_usage() -> @provider.LanguageModelV4Usage {
  @provider.LanguageModelV4Usage::unknown()
}

///|
/// AI SDK-style spelling of `create_null_language_model_usage`.
pub fn createNullLanguageModelUsage() -> @provider.LanguageModelV4Usage {
  create_null_language_model_usage()
}

///|
fn add_optional_token_counts(first : Int?, second : Int?) -> Int? {
  if first is None && second is None {
    None
  } else {
    Some(first.unwrap_or(0) + second.unwrap_or(0))
  }
}

///|
/// Add V4 language-model usage across high-level generation steps.
///
/// Missing counters remain missing only when every contributing step omitted
/// them. Provider-native raw usage cannot be meaningfully merged and is
/// therefore intentionally absent from the aggregate.
pub fn add_language_model_usage(
  first : @provider.LanguageModelV4Usage,
  second : @provider.LanguageModelV4Usage,
) -> @provider.LanguageModelV4Usage {
  {
    input_tokens: {
      total: add_optional_token_counts(
        first.input_tokens.total,
        second.input_tokens.total,
      ),
      no_cache: add_optional_token_counts(
        first.input_tokens.no_cache,
        second.input_tokens.no_cache,
      ),
      cache_read: add_optional_token_counts(
        first.input_tokens.cache_read,
        second.input_tokens.cache_read,
      ),
      cache_write: add_optional_token_counts(
        first.input_tokens.cache_write,
        second.input_tokens.cache_write,
      ),
    },
    output_tokens: {
      total: add_optional_token_counts(
        first.output_tokens.total,
        second.output_tokens.total,
      ),
      text: add_optional_token_counts(
        first.output_tokens.text,
        second.output_tokens.text,
      ),
      reasoning: add_optional_token_counts(
        first.output_tokens.reasoning,
        second.output_tokens.reasoning,
      ),
    },
    raw: None,
  }
}

///|
/// AI SDK-style camel-case spelling.
pub fn addLanguageModelUsage(
  first : @provider.LanguageModelV4Usage,
  second : @provider.LanguageModelV4Usage,
) -> @provider.LanguageModelV4Usage {
  add_language_model_usage(first, second)
}

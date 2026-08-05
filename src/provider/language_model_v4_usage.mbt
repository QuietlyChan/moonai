///|
/// Input-token accounting for the V4 language-model contract.
///
/// AI SDK keeps total, uncached, cache-read, and cache-write values separate.
/// The older `Usage` type only has a total plus cache counters, so the V4
/// shape intentionally uses optional values and preserves what a provider did
/// (or did not) report.
pub(all) struct LanguageModelV4InputTokens {
  total : Int?
  no_cache : Int?
  cache_read : Int?
  cache_write : Int?
} derive(Debug, Eq)

///|
/// Output-token accounting for the V4 language-model contract.
pub(all) struct LanguageModelV4OutputTokens {
  total : Int?
  text : Int?
  reasoning : Int?
} derive(Debug, Eq)

///|
/// Usage information returned by a V4 language model.
pub(all) struct LanguageModelV4Usage {
  input_tokens : LanguageModelV4InputTokens
  output_tokens : LanguageModelV4OutputTokens
  raw : Json?
} derive(Debug, Eq)

///|
/// Construct a V4 usage value for a provider response that did not report
/// token accounting. This differs from `zero`: unknown counters must remain
/// absent so callers do not mistake missing telemetry for measured zero use.
pub fn LanguageModelV4Usage::unknown() -> LanguageModelV4Usage {
  {
    input_tokens: {
      total: None,
      no_cache: None,
      cache_read: None,
      cache_write: None,
    },
    output_tokens: { total: None, text: None, reasoning: None },
    raw: None,
  }
}

///|
/// Construct an empty V4 usage value.
pub fn LanguageModelV4Usage::zero() -> LanguageModelV4Usage {
  {
    input_tokens: {
      total: Some(0),
      no_cache: Some(0),
      cache_read: Some(0),
      cache_write: Some(0),
    },
    output_tokens: { total: Some(0), text: Some(0), reasoning: Some(0) },
    raw: None,
  }
}

///|
fn v4_usage_int_field(json : Json, field : String) -> Int? {
  match json {
    Object(values) =>
      match values.get(field) {
        Some(Number(value, ..)) => Some(value.to_int())
        _ => None
      }
    _ => None
  }
}

///|
fn v4_usage_nested_int_field(
  json : Json,
  object_field : String,
  field : String,
) -> Int? {
  match json {
    Object(values) =>
      match values.get(object_field) {
        Some(Object(nested)) =>
          match nested.get(field) {
            Some(Number(value, ..)) => Some(value.to_int())
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// Decode the token usage object shared by Open Responses-compatible APIs.
/// Missing counters remain optional while derived text/non-cache counters
/// follow the AI SDK V4 convention of subtracting absent values as zero.
pub fn LanguageModelV4Usage::from_token_usage_json(
  raw_usage : Json?,
) -> LanguageModelV4Usage {
  match raw_usage {
    Some(usage) if !(usage is Null) => {
      let input_tokens = v4_usage_int_field(usage, "input_tokens")
      let cached_input_tokens = v4_usage_nested_int_field(
        usage, "input_tokens_details", "cached_tokens",
      )
      let output_tokens = v4_usage_int_field(usage, "output_tokens")
      let reasoning_tokens = v4_usage_nested_int_field(
        usage, "output_tokens_details", "reasoning_tokens",
      )
      {
        input_tokens: {
          total: input_tokens,
          no_cache: Some(
            input_tokens.unwrap_or(0) - cached_input_tokens.unwrap_or(0),
          ),
          cache_read: cached_input_tokens,
          cache_write: None,
        },
        output_tokens: {
          total: output_tokens,
          text: Some(output_tokens.unwrap_or(0) - reasoning_tokens.unwrap_or(0)),
          reasoning: reasoning_tokens,
        },
        raw: Some(usage),
      }
    }
    _ => LanguageModelV4Usage::unknown()
  }
}

///|
/// Attach the provider-native usage object.
pub fn LanguageModelV4Usage::with_raw(
  self : LanguageModelV4Usage,
  raw : Json?,
) -> LanguageModelV4Usage {
  { input_tokens: self.input_tokens, output_tokens: self.output_tokens, raw }
}

///|
/// Convert normalized wire usage into the lossless V4 shape.
pub fn LanguageModelV4Usage::from_usage(usage : Usage) -> LanguageModelV4Usage {
  {
    input_tokens: {
      total: Some(usage.input_tokens),
      no_cache: Some(
        (usage.input_tokens -
        usage.cached_input_tokens -
        usage.cache_write_input_tokens).max(0),
      ),
      cache_read: Some(usage.cached_input_tokens),
      cache_write: Some(usage.cache_write_input_tokens),
    },
    output_tokens: {
      total: Some(usage.output_tokens),
      // The wire contract does not separate text and reasoning output.
      text: Some((usage.output_tokens - usage.reasoning_tokens).max(0)),
      reasoning: Some(usage.reasoning_tokens),
    },
    raw: None,
  }
}

///|
/// Convert V4 usage to the normalized usage used by current wire adapters.
pub fn LanguageModelV4Usage::to_usage(self : LanguageModelV4Usage) -> Usage {
  let input_total = self.input_tokens.total.unwrap_or(0)
  let cache_read = self.input_tokens.cache_read.unwrap_or(0)
  let cache_write = self.input_tokens.cache_write.unwrap_or(0)
  let output_total = self.output_tokens.total.unwrap_or(0)
  let reasoning = self.output_tokens.reasoning.unwrap_or(0)
  {
    input_tokens: input_total,
    output_tokens: output_total,
    total_tokens: input_total + output_total,
    reasoning_tokens: reasoning,
    cached_input_tokens: cache_read,
    cache_write_input_tokens: cache_write,
  }
}

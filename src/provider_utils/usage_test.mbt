///|
test "null language model usage leaves every counter unavailable" {
  let usage = create_null_language_model_usage()
  assert_eq(usage.input_tokens.total, None)
  assert_eq(usage.input_tokens.no_cache, None)
  assert_eq(usage.input_tokens.cache_read, None)
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.total, None)
  assert_eq(usage.output_tokens.text, None)
  assert_eq(usage.output_tokens.reasoning, None)
  assert_eq(usage.raw, None)
  assert_eq(createNullLanguageModelUsage(), usage)
}

///|
test "add language model usage sums known counters across steps" {
  let first = @provider.LanguageModelV4Usage::{
    input_tokens: {
      total: Some(3),
      no_cache: Some(2),
      cache_read: Some(1),
      cache_write: None,
    },
    output_tokens: { total: Some(4), text: Some(3), reasoning: Some(1) },
    raw: Some({ "step": 1 }),
  }
  let second = @provider.LanguageModelV4Usage::{
    input_tokens: {
      total: Some(5),
      no_cache: None,
      cache_read: Some(2),
      cache_write: Some(1),
    },
    output_tokens: { total: Some(6), text: Some(4), reasoning: Some(2) },
    raw: Some({ "step": 2 }),
  }
  assert_eq(add_language_model_usage(first, second), {
    input_tokens: {
      total: Some(8),
      no_cache: Some(2),
      cache_read: Some(3),
      cache_write: Some(1),
    },
    output_tokens: { total: Some(10), text: Some(7), reasoning: Some(3) },
    raw: None,
  })
  assert_eq(
    add_language_model_usage(
      @provider.LanguageModelV4Usage::unknown(),
      @provider.LanguageModelV4Usage::unknown(),
    ),
    @provider.LanguageModelV4Usage::unknown(),
  )
}

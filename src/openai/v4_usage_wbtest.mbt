///|
test "OpenAI Chat V4 usage preserves optional cache-write accounting" {
  let raw : Json = {
    "prompt_tokens": 12,
    "completion_tokens": 7,
    "prompt_tokens_details": { "cached_tokens": 3 },
    "completion_tokens_details": { "reasoning_tokens": 2 },
  }
  let usage = openai_chat_v4_usage(Some(raw))
  assert_eq(usage.input_tokens.total, Some(12))
  assert_eq(usage.input_tokens.no_cache, Some(9))
  assert_eq(usage.input_tokens.cache_read, Some(3))
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.text, Some(5))
  assert_eq(usage.output_tokens.reasoning, Some(2))
  assert_eq(usage.raw, Some(raw))
}

///|
test "OpenAI completion V4 usage keeps unreported totals absent" {
  let raw : Json = { "completion_tokens": 4 }
  let usage = openai_completion_v4_usage(Some(raw))
  assert_eq(usage.input_tokens.total, None)
  assert_eq(usage.input_tokens.no_cache, Some(0))
  assert_eq(usage.input_tokens.cache_read, None)
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.total, Some(4))
  assert_eq(usage.output_tokens.text, Some(4))
  assert_eq(usage.output_tokens.reasoning, None)
  assert_eq(usage.raw, Some(raw))
}

///|
test "OpenAI Responses V4 usage subtracts cache-write tokens" {
  let raw : Json = {
    "input_tokens": 12,
    "output_tokens": 7,
    "input_tokens_details": { "cached_tokens": 3, "cache_write_tokens": 2 },
    "output_tokens_details": { "reasoning_tokens": 4 },
  }
  let usage = openai_responses_v4_usage(Some(raw))
  assert_eq(usage.input_tokens.total, Some(12))
  assert_eq(usage.input_tokens.no_cache, Some(7))
  assert_eq(usage.input_tokens.cache_read, Some(3))
  assert_eq(usage.input_tokens.cache_write, Some(2))
  assert_eq(usage.output_tokens.total, Some(7))
  assert_eq(usage.output_tokens.text, Some(3))
  assert_eq(usage.output_tokens.reasoning, Some(4))
  assert_eq(usage.raw, Some(raw))
}

///|
test "OpenAI V4 usage keeps a missing usage object unknown" {
  assert_eq(
    openai_chat_v4_usage(None),
    @provider.LanguageModelV4Usage::unknown(),
  )
  assert_eq(
    openai_completion_v4_usage(None),
    @provider.LanguageModelV4Usage::unknown(),
  )
  assert_eq(
    openai_responses_v4_usage(None),
    @provider.LanguageModelV4Usage::unknown(),
  )
}

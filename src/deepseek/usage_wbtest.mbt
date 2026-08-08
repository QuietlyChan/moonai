///|
test "DeepSeek V4 usage preserves cache and reasoning accounting" {
  let raw : Json = {
    "prompt_tokens": 17,
    "completion_tokens": 11,
    "total_tokens": 28,
    "prompt_cache_hit_tokens": 5,
    "prompt_cache_miss_tokens": 12,
    "completion_tokens_details": { "reasoning_tokens": 7 },
  }
  let usage = convert_deepseek_usage(Some(raw))
  assert_eq(usage.input_tokens.total, Some(17))
  assert_eq(usage.input_tokens.no_cache, Some(12))
  assert_eq(usage.input_tokens.cache_read, Some(5))
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.total, Some(11))
  assert_eq(usage.output_tokens.text, Some(4))
  assert_eq(usage.output_tokens.reasoning, Some(7))
  assert_eq(usage.raw, Some(raw))
}

///|
test "DeepSeek V4 usage defaults missing counters to zero" {
  let raw = Json::empty_object()
  let usage = convert_deepseek_usage(Some(raw))
  assert_eq(usage.input_tokens.total, Some(0))
  assert_eq(usage.input_tokens.no_cache, Some(0))
  assert_eq(usage.input_tokens.cache_read, Some(0))
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.total, Some(0))
  assert_eq(usage.output_tokens.text, Some(0))
  assert_eq(usage.output_tokens.reasoning, Some(0))
  assert_eq(usage.raw, Some(raw))
}

///|
test "DeepSeek V4 usage is unknown when the API omits usage" {
  assert_eq(
    convert_deepseek_usage(None),
    @provider.LanguageModelV4Usage::unknown(),
  )
  assert_eq(
    convert_deepseek_usage(Some(Json::null())),
    @provider.LanguageModelV4Usage::unknown(),
  )
}

///|
test "DeepSeek metadata uses the first provider namespace segment" {
  let metadata = deepseek_usage_metadata(
    { "prompt_cache_hit_tokens": 3 },
    "custom.deepseek.chat",
  )
  assert_eq(metadata.length(), 1)
  json_inspect(metadata["custom"], content={ "promptCacheHitTokens": 3 })
  let empty = deepseek_usage_metadata(Json::empty_object(), "deepseek.chat")
  assert_true(empty.get("deepseek") is Some({ .. }))
}

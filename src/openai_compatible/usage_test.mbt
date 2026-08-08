///|
test "OpenAI-compatible V4 usage preserves cache and reasoning fields" {
  let value = @json.parse(
    "{\"prompt_tokens\":12,\"completion_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":3},\"completion_tokens_details\":{\"reasoning_tokens\":4}}",
  )
  let usage = convert_openai_compatible_chat_usage(Some(value))
  assert_eq(usage.input_tokens.total, Some(12))
  assert_eq(usage.input_tokens.no_cache, Some(9))
  assert_eq(usage.input_tokens.cache_read, Some(3))
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.total, Some(7))
  assert_eq(usage.output_tokens.text, Some(3))
  assert_eq(usage.output_tokens.reasoning, Some(4))
  assert_eq(usage.raw, Some(value))
}

///|
test "OpenAI-compatible V4 usage keeps unsupported details only in raw" {
  let value = @json.parse(
    "{\"prompt_tokens\":12,\"completion_tokens\":7,\"total_tokens\":25,\"prompt_tokens_details\":{\"cache_write_tokens\":2},\"completion_tokens_details\":{\"reasoning_tokens\":4}}",
  )
  let usage = convert_openai_compatible_chat_usage(Some(value))
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.reasoning, Some(4))
  assert_eq(usage.raw, Some(value))
}

///|
test "OpenAI-compatible V4 usage is unknown when omitted" {
  assert_eq(
    convert_openai_compatible_chat_usage(None),
    @provider.LanguageModelV4Usage::unknown(),
  )
  assert_eq(
    convert_openai_compatible_chat_usage(Some(Json::null())),
    @provider.LanguageModelV4Usage::unknown(),
  )
}

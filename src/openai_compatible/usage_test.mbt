///|
test "OpenAI-compatible usage derives total tokens when omitted" {
  let value = @json.parse(
    "{\"prompt_tokens\":12,\"completion_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":3}}",
  )
  let usage = convert_openai_compatible_chat_usage(value)
  assert_eq(usage.input_tokens, 12)
  assert_eq(usage.output_tokens, 7)
  assert_eq(usage.total_tokens, 19)
  assert_eq(usage.cached_input_tokens, 3)
}

///|
test "OpenAI-compatible usage preserves explicit total and cache-write tokens" {
  let value = @json.parse(
    "{\"prompt_tokens\":12,\"completion_tokens\":7,\"total_tokens\":25,\"prompt_tokens_details\":{\"cache_write_tokens\":2},\"completion_tokens_details\":{\"reasoning_tokens\":4}}",
  )
  let usage = convert_openai_compatible_chat_usage(value)
  assert_eq(usage.total_tokens, 25)
  assert_eq(usage.cache_write_input_tokens, 2)
  assert_eq(usage.reasoning_tokens, 4)
}

///|
test "Alibaba usage derives total tokens and keeps cache accounting" {
  let value = @json.parse(
    "{\"prompt_tokens\":12,\"completion_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":3,\"cache_creation_input_tokens\":2},\"completion_tokens_details\":{\"reasoning_tokens\":4}}",
  )
  let usage = convert_alibaba_chat_usage(value)
  assert_eq(usage.input_tokens, 12)
  assert_eq(usage.output_tokens, 7)
  assert_eq(usage.total_tokens, 19)
  assert_eq(usage.cached_input_tokens, 3)
  assert_eq(usage.cache_write_input_tokens, 2)
  assert_eq(usage.reasoning_tokens, 4)
}

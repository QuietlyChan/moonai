///|
test "Alibaba V4 usage preserves cache accounting" {
  let value = @json.parse(
    "{\"prompt_tokens\":12,\"completion_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":3,\"cache_creation_input_tokens\":2},\"completion_tokens_details\":{\"reasoning_tokens\":4}}",
  )
  let usage = convert_alibaba_chat_usage(Some(value))
  assert_eq(usage.input_tokens.total, Some(12))
  assert_eq(usage.input_tokens.no_cache, Some(7))
  assert_eq(usage.input_tokens.cache_read, Some(3))
  assert_eq(usage.input_tokens.cache_write, Some(2))
  assert_eq(usage.output_tokens.total, Some(7))
  assert_eq(usage.output_tokens.text, Some(3))
  assert_eq(usage.output_tokens.reasoning, Some(4))
  assert_eq(usage.raw, Some(value))
}

///|
test "AlibabaUsage preserves the provider-specific raw usage shape" {
  let value = @json.parse(
    "{\"prompt_tokens\":200,\"completion_tokens\":75,\"total_tokens\":275,\"prompt_tokens_details\":{\"cached_tokens\":120,\"cache_creation_input_tokens\":50},\"completion_tokens_details\":{\"reasoning_tokens\":25}}",
  )
  let usage = AlibabaUsage::from_json(value).unwrap()
  assert_eq(
    usage,
    AlibabaUsage::new(
      prompt_tokens=200,
      completion_tokens=75,
      total_tokens=275,
      prompt_tokens_details=AlibabaPromptTokensDetails::new(
        cached_tokens=120,
        cache_creation_input_tokens=50,
      ),
      completion_tokens_details=AlibabaCompletionTokensDetails::new(
        reasoning_tokens=25,
      ),
    ),
  )
  assert_eq(usage.to_json(), value)
  let converted = convert_alibaba_chat_usage(Some(usage.to_json()))
  assert_eq(converted.input_tokens.total, Some(200))
  assert_eq(converted.input_tokens.no_cache, Some(30))
  assert_eq(converted.input_tokens.cache_read, Some(120))
  assert_eq(converted.input_tokens.cache_write, Some(50))
  assert_eq(converted.output_tokens.total, Some(75))
  assert_eq(converted.output_tokens.text, Some(50))
  assert_eq(converted.output_tokens.reasoning, Some(25))
}

///|
test "AlibabaUsage maps null and absent wire fields to None" {
  let usage = AlibabaUsage::from_json(
    @json.parse(
      "{\"prompt_tokens\":null,\"prompt_tokens_details\":null,\"completion_tokens_details\":{\"reasoning_tokens\":null}}",
    ),
  ).unwrap()
  assert_eq(usage.prompt_tokens, None)
  assert_eq(usage.completion_tokens, None)
  assert_eq(usage.total_tokens, None)
  assert_eq(usage.prompt_tokens_details, None)
  assert_eq(
    usage.completion_tokens_details,
    Some(AlibabaCompletionTokensDetails::new()),
  )
}

///|
test "Alibaba V4 usage keeps provider-specific zero cache counters when omitted" {
  for usage in [None, Some(Json::null())] {
    let converted = convert_alibaba_chat_usage(usage)
    assert_eq(converted.input_tokens.total, None)
    assert_eq(converted.input_tokens.no_cache, Some(0))
    assert_eq(converted.input_tokens.cache_read, None)
    assert_eq(converted.input_tokens.cache_write, Some(0))
    assert_eq(converted.output_tokens.total, None)
    assert_eq(converted.output_tokens.text, None)
    assert_eq(converted.output_tokens.reasoning, None)
    assert_eq(converted.raw, None)
  }
}

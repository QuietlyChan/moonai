///|
fn compatible_warning_test_prompt() -> @provider.LanguageModelV4Prompt {
  @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[@provider.V4PromptText(text="answer", provider_options=Map([]))],
      provider_options=Map([]),
    ),
  ])
}

///|
test "OpenAI-compatible warns when JSON Schema support is not enabled" {
  let options = @provider.LanguageModelV4CallOptions::new(
    compatible_warning_test_prompt(),
    response_format=@provider.LanguageModelV4ResponseFormat::json(
      name="answer_schema",
      schema={ "type": "object" },
    ),
    provider_options={ "localTest": { "messages": [] } },
  )
  let warnings = prepare_compatible_v4_chat_request(
      "test-model", options, true, true, "local-test.chat", false, false, true, default_openai_compatible_v4_prompt_converter,
    ).warnings
  assert_eq(warnings.length(), 2)
  assert_true(
    warnings[0]
    is @provider.Compatibility(feature="providerOptions.messages", ..),
  )
  assert_true(
    warnings[1] is @provider.Unsupported(feature="responseFormat", ..),
  )
}

///|
test "OpenAI-compatible reports unsupported topK for chat and completion" {
  let options = @provider.LanguageModelV4CallOptions::new(
    compatible_warning_test_prompt(),
    top_k=20.0,
  )
  let chat = prepare_compatible_v4_chat_request(
    "test-model", options, true, false, "local-test.chat", false, false, true, default_openai_compatible_v4_prompt_converter,
  )
  assert_eq(chat.warnings.length(), 1)
  assert_true(chat.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_false(chat.body.stringify().contains("top_k"))

  let completion = prepare_compatible_completion_v4_request(
    "test-model", options, "local-test.completion", false, false,
  )
  assert_eq(completion.warnings.length(), 1)
  assert_true(
    completion.warnings[0] is @provider.Unsupported(feature="topK", ..),
  )
  assert_false(completion.body.stringify().contains("top_k"))
}

///|
test "OpenAI-compatible capability warnings follow provider switches" {
  let options = @provider.LanguageModelV4CallOptions::new(
    compatible_warning_test_prompt(),
    top_k=20.0,
    frequency_penalty=0.4,
  )
  let prepared = prepare_compatible_v4_chat_request(
    "qwen-test", options, true, false, "alibaba.chat", true, true, false, default_openai_compatible_v4_prompt_converter,
  )
  assert_eq(prepared.warnings.length(), 1)
  assert_true(
    prepared.warnings[0]
    is @provider.Unsupported(feature="frequencyPenalty", ..),
  )
  assert_true(prepared.body.stringify().contains("top_k"))
  assert_false(prepared.body.stringify().contains("frequency_penalty"))
}

///|
test "OpenAI-compatible image settings report unsupported warnings" {
  let resolution = resolve_compatible_options(
    Map([]),
    "openai-compatible.image",
    image_reserved_fields(),
  )
  let warnings = compatible_image_request_warnings(
    Some("16:9"),
    Some(7),
    resolution,
  )
  assert_eq(warnings.length(), 2)
  assert_true(warnings[0] is @provider.Unsupported(feature="aspectRatio", ..))
  assert_true(warnings[1] is @provider.Unsupported(feature="seed", ..))
}

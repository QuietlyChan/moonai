///|
test "OpenAI-compatible warns when JSON Schema support is not enabled" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("answer")],
    response_format=@provider.ResponseFormat::json(name="answer_schema", schema={
      "type": "object",
    }),
    provider_options={ "localTest": { "messages": [] } },
  )
  let warnings = prepare_compatible_chat_request(
      "test-model", options, false, true, true, "local-test.chat", false, false,
      true, default_openai_compatible_prompt_converter,
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
  let chat = prepare_compatible_chat_request(
    "test-model",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("answer")],
      top_k=20.0,
    ),
    false,
    true,
    false,
    "local-test.chat",
    false,
    false,
    true,
    default_openai_compatible_prompt_converter,
  )
  assert_eq(chat.warnings.length(), 1)
  assert_true(chat.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_false(chat.body.stringify().contains("top_k"))

  let completion_options = @provider.CompletionOptions::new(
    "MoonBit is",
    top_k=20.0,
  )
  let resolution = resolve_compatible_options(
    completion_options.provider_options,
    "local-test.completion",
    completion_reserved_fields(),
  )
  let completion_warnings = compatible_completion_request_warnings(
    completion_options, resolution,
  )
  assert_eq(completion_warnings.length(), 1)
  assert_true(
    completion_warnings[0] is @provider.Unsupported(feature="topK", ..),
  )
  assert_false(
    encode_completion_request("test-model", completion_options)
    .stringify()
    .contains("top_k"),
  )
}

///|
test "OpenAI-compatible capability warnings follow provider switches" {
  let prepared = prepare_compatible_chat_request(
    "qwen-test",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      top_k=20.0,
      frequency_penalty=0.4,
    ),
    false,
    true,
    false,
    "alibaba.chat",
    true,
    true,
    false,
    default_openai_compatible_prompt_converter,
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
  let options = @provider.ImageCallOptions::new(
    "draw",
    aspect_ratio="16:9",
    seed=7,
  )
  let resolution = resolve_compatible_options(
    options.provider_options,
    "openai-compatible.image",
    image_reserved_fields(),
  )
  let warnings = compatible_image_request_warnings(options, resolution)
  assert_eq(warnings.length(), 2)
  assert_true(warnings[0] is @provider.Unsupported(feature="aspectRatio", ..))
  assert_true(warnings[1] is @provider.Unsupported(feature="seed", ..))
}

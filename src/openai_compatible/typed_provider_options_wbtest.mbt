///|
fn compatible_test_prompt(text : String) -> @provider.LanguageModelV4Prompt {
  @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[@provider.V4PromptText(text~, provider_options=Map([]))],
      provider_options=Map([]),
    ),
  ])
}

///|
test "typed OpenAI-compatible chat options encode through V4" {
  let options = @provider.LanguageModelV4CallOptions::new(
    compatible_test_prompt("hello"),
    provider_options=OpenAICompatibleLanguageModelChatOptions::new(
      user="user-typed",
      reasoning_effort="high",
      text_verbosity="low",
      strict_json_schema=false,
    ).to_provider_options(provider_name="testProvider"),
  )
  let prepared = prepare_compatible_v4_chat_request(
    "chat-model", options, false, false, "test-provider.chat", false, false, true,
    default_openai_compatible_v4_prompt_converter,
  )
  json_inspect(prepared.body, content={
    "model": "chat-model",
    "messages": [{ "role": "user", "content": "hello" }],
    "user": "user-typed",
    "reasoning_effort": "high",
    "verbosity": "low",
  })
}

///|
test "typed OpenAI-compatible completion options encode through V4" {
  let options = @provider.LanguageModelV4CallOptions::new(
    compatible_test_prompt("MoonBit"),
    provider_options=OpenAICompatibleLanguageModelCompletionOptions::new(
      echo=true,
      logit_bias={ "42": -2.0 },
      suffix="provider",
      user="user-typed",
    ).to_provider_options(provider_name="testProvider"),
  )
  let prepared = prepare_compatible_completion_v4_request(
    "completion-model", options, "test-provider.completion", false, false,
  )
  json_inspect(prepared.body, content={
    "model": "completion-model",
    "prompt": "user:\nMoonBit\n\nassistant:\n",
    "stop": ["\nuser:"],
    "echo": true,
    "logit_bias": { "42": -2.0 },
    "suffix": "provider",
    "user": "user-typed",
  })
}

///|
test "typed OpenAI-compatible embedding options encode through V4" {
  let provider_options = OpenAICompatibleEmbeddingModelOptions::new(
    dimensions=64,
    user="user-typed",
  ).to_provider_options(provider_name="testProvider")
  let resolution = resolve_compatible_options(
    provider_options,
    "test-provider.embedding",
    embedding_reserved_fields(),
  )
  json_inspect(
    encode_embedding_request_data(
      "embedding-model",
      ["hello"],
      resolution.values,
    ),
    content={
      "model": "embedding-model",
      "input": ["hello"],
      "encoding_format": "float",
      "dimensions": 64,
      "user": "user-typed",
    },
  )
}

///|
test "typed OpenAI-compatible image options preserve loose extensions" {
  let provider_options = OpenAICompatibleImageModelOptions::new(
    size="auto",
    quality="high",
    output_format="webp",
    output_compression=80,
    background="transparent",
    extensions={ "vendor_flag": true },
  ).to_provider_options(provider_name="testProvider")
  let resolution = resolve_compatible_options(
    provider_options,
    "test-provider.image",
    image_reserved_fields(),
  )
  json_inspect(
    encode_image_request_data(
      "image-model",
      Some("A MoonBit logo"),
      1,
      Some("1024x1024"),
      resolution.values,
      false,
    ),
    content={
      "model": "image-model",
      "prompt": "A MoonBit logo",
      "n": 1,
      "size": "auto",
      "vendor_flag": true,
      "quality": "high",
      "output_format": "webp",
      "output_compression": 80,
      "background": "transparent",
    },
  )
}

///|
test "typed OpenAI-compatible image options validate compression" {
  try OpenAICompatibleImageModelOptions::new(output_compression=101) catch {
    Failure::Failure(message) =>
      assert_true(message.contains("between 0 and 100"))
    error => fail("unexpected image option error: \{error}")
  } noraise {
    _ => fail("expected invalid image compression to be rejected")
  }
}

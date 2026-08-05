///|
test "typed OpenAI-compatible chat options encode through the provider namespace" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options=OpenAICompatibleLanguageModelChatOptions::new(
      user="user-typed",
      reasoning_effort="high",
      text_verbosity="low",
      strict_json_schema=false,
    ).to_provider_options(provider_name="testProvider"),
  )
  json_inspect(
    encode_chat_request(
      "chat-model",
      options,
      stream=false,
      provider_name="test-provider.chat",
    ),
    content={
      "model": "chat-model",
      "messages": [{ "role": "user", "content": "hello" }],
      "user": "user-typed",
      "reasoning_effort": "high",
      "verbosity": "low",
    },
  )
}

///|
test "typed OpenAI-compatible completion options override standard fallbacks" {
  let options = @provider.CompletionOptions::new(
    "MoonBit",
    suffix="top-level",
    provider_options=OpenAICompatibleLanguageModelCompletionOptions::new(
      echo=true,
      logit_bias={ "42": -2.0 },
      suffix="provider",
      user="user-typed",
    ).to_provider_options(provider_name="testProvider"),
  )
  json_inspect(
    encode_completion_request(
      "completion-model",
      options,
      stream=false,
      provider_name="test-provider.completion",
    ),
    content={
      "model": "completion-model",
      "prompt": "MoonBit",
      "suffix": "provider",
      "echo": true,
      "logit_bias": { "42": -2.0 },
      "user": "user-typed",
    },
  )
}

///|
test "typed OpenAI-compatible embedding options override standard fallbacks" {
  let options = @provider.EmbeddingOptions::new(
    dimensions=256,
    user="top-level",
    provider_options=OpenAICompatibleEmbeddingModelOptions::new(
      dimensions=64,
      user="user-typed",
    ).to_provider_options(provider_name="testProvider"),
  )
  json_inspect(
    encode_embedding_request(
      "embedding-model",
      ["hello"],
      options,
      provider_name="test-provider.embedding",
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
  let options = @provider.ImageCallOptions::new(
    "A MoonBit logo",
    size="1024x1024",
    provider_options=OpenAICompatibleImageModelOptions::new(
      size="auto",
      quality="high",
      output_format="webp",
      output_compression=80,
      background="transparent",
      extensions={ "vendor_flag": true },
    ).to_provider_options(provider_name="testProvider"),
  )
  json_inspect(
    encode_image_request(
      "image-model",
      options,
      provider_name="test-provider.image",
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

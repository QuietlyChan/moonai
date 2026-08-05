///|
test "provider registry resolves every concrete provider and model family" {
  let openai = @openai.create_openai(api_key="test-key")
  let compatible = @openai_compatible.create_openai_compatible(
    provider_name="gateway",
    base_url="https://example.com/v1",
    api_key="test-key",
  )
  let open_responses = @open_responses.create_open_responses(
    provider_name="local-responses",
    url="https://example.com/v1/responses",
    api_key="test-key",
  )
  let anthropic = @anthropic.create_anthropic(api_key="test-key")
  let alibaba = @alibaba.create_alibaba(api_key="test-key")
  let deepseek = @deepseek.create_deepseek(api_key="test-key")
  let minimax = @minimax.create_minimax(api_key="test-key")
  let registry = ProviderRegistry::new()
    .with_provider("openai", openai)
    .with_provider("gateway", compatible)
    .with_provider("responses", open_responses)
    .with_provider("anthropic", anthropic)
    .with_provider("alibaba", alibaba)
    .with_provider("deepseek", deepseek)
    .with_provider("minimax", minimax)
  assert_eq(openai.specification_version(), "v4")
  assert_eq(compatible.specification_version(), "v4")
  assert_eq(open_responses.specification_version(), "v4")
  assert_eq(anthropic.specification_version(), "v4")
  assert_eq(alibaba.specification_version(), "v4")
  assert_eq(deepseek.specification_version(), "v4")
  assert_eq(minimax.specification_version(), "v4")
  assert_eq(registry.provider_ids().length(), 7)
  for
    id in [
      "openai:gpt-4.1", "gateway:chat-model", "responses:response-model", "anthropic:claude-model",
      "alibaba:qwen-model", "deepseek:deepseek-chat", "minimax:minimax-m3",
    ] {
    assert_true(registry.language_model(id).model_id() != "")
  }
  let responses_model = registry.language_model("responses:response-model")
  assert_eq(responses_model.specification_version(), "v4")
  assert_eq(responses_model.provider(), "local-responses.responses")
  assert_eq(responses_model.model_id(), "response-model")
  assert_eq(
    registry.completion_model("openai:gpt-instruct").model_id(),
    "gpt-instruct",
  )
  assert_eq(
    registry.embedding_model("gateway:embed-model").model_id(),
    "embed-model",
  )
  assert_eq(
    registry.image_model("openai:gpt-image-1").model_id(),
    "gpt-image-1",
  )
  assert_eq(registry.video_model("alibaba:wan-model").model_id(), "wan-model")
  assert_eq(registry.video_model("minimax:MiniMax-H3").model_id(), "MiniMax-H3")
  assert_eq(
    registry.speech_model("openai:gpt-4o-mini-tts").model_id(),
    "gpt-4o-mini-tts",
  )
  assert_eq(
    registry.transcription_model("openai:gpt-4o-transcribe").model_id(),
    "gpt-4o-transcribe",
  )
  assert_eq(
    registry
    .speech_translation_model("openai:gpt-4o-mini-transcribe")
    .model_id(),
    "gpt-4o-mini-transcribe",
  )
  assert_eq(
    registry.realtime_model("openai:gpt-realtime").model_id(),
    "gpt-realtime",
  )
  assert_eq(registry.files("openai").provider(), "openai.files")
  assert_eq(registry.skills("anthropic").provider(), "anthropic.skills")
}

///|
test "provider registry preserves model ids after the first separator" {
  let openai = @openai.create_openai(api_key="test-key")
  let providers : Map[String, &@provider.Provider] = Map([("openai", openai)])
  let registry = createProviderRegistry(providers, separator="/")
  assert_eq(registry.separator(), "/")
  assert_eq(
    registry.language_model("openai/model/version").model_id(),
    "model/version",
  )
}

///|
test "provider registry applies language-model middleware" {
  let middleware = @model.LanguageModelV4Middleware::new(
    provider="wrapped-provider",
  )
  let registry = ProviderRegistry::new(language_model_middleware=middleware).with_provider(
    "custom",
    @openai.create_openai(api_key="test-key"),
  )
  let resolved = registry.language_model("custom:model")
  assert_eq(resolved.provider(), "wrapped-provider")
  assert_eq(resolved.model_id(), "model")
}

///|
test "provider registry applies language-model middleware metadata" {
  let middleware = @model.LanguageModelV4Middleware::new(
    provider="wrapped-v4-provider",
    model_id="wrapped-v4-model",
  )
  let registry = ProviderRegistry::new(language_model_middleware=middleware).with_provider(
    "custom",
    @openai.create_openai(api_key="test-key"),
  )
  let resolved = registry.language_model("custom:model")
  assert_eq(resolved.provider(), "wrapped-v4-provider")
  assert_eq(resolved.model_id(), "wrapped-v4-model")
}

///|
test "provider registry applies image-model middleware" {
  let middleware = @model.ImageModelV4Middleware::new(
    provider="wrapped-image-provider",
    model_id="wrapped-image-model",
    max_images_per_call=2,
  )
  let registry = ProviderRegistry::new(image_model_middleware=middleware).with_provider(
    "custom",
    @openai.create_openai(api_key="test-key"),
  )
  let resolved = registry.image_model("custom:image")
  assert_eq(resolved.provider(), "wrapped-image-provider")
  assert_eq(resolved.model_id(), "wrapped-image-model")
  assert_eq(resolved.max_images_per_call(), Some(2))
}

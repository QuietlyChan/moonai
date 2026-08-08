///|
test "provider settings propagate to every compatible model" {
  let provider = create_openai_compatible(
    provider_name="local-test",
    base_url="https://example.com/v1",
    query_params={ "api-version": "2026-08" },
    supports_structured_outputs=true,
  )
  let chat = provider.chat_language_model("chat-model")
  let completion = provider.completion_language_model("completion-model")
  let embedding = provider.embedding_model_value("embedding-model")
  let image = provider.image_model_value("image-model")
  assert_eq(
    chat.chat_completions_url(),
    "https://example.com/v1/chat/completions?api-version=2026-08",
  )
  assert_true(chat.config.supports_structured_outputs)
  assert_eq(
    completion.completions_url(),
    "https://example.com/v1/completions?api-version=2026-08",
  )
  assert_eq(
    embedding.embeddings_url(),
    "https://example.com/v1/embeddings?api-version=2026-08",
  )
  assert_eq(
    image.generations_url(),
    "https://example.com/v1/images/generations?api-version=2026-08",
  )
}

///|
test "compatible chat request transform is stored in model config" {
  let provider = create_openai_compatible(
    provider_name="proxy",
    base_url="https://example.com/v1",
    transform_request_body=body => {
      let fields = match body {
        Object(value) => value
        _ => Map([])
      }
      fields["proxy_mode"] = Json::boolean(true)
      Json::object(fields)
    },
  )
  let model = provider.chat_language_model("chat-model")
  json_inspect(
    (model.config.transform_request_body)({ "model": "chat-model" }),
    content={ "model": "chat-model", "proxy_mode": true },
  )
}

///|
test "OpenAI Compatible public factory exposes the AI SDK provider contract" {
  let provider = createOpenAICompatible(
    provider_name="local",
    base_url="https://example.test/v1",
    api_key="test-key",
  )
  let generic_provider = provider as &@provider.ProviderV4
  assert_eq(generic_provider.specification_version(), "v4")
  let language_model = generic_provider.language_model("chat-model")
  assert_eq(language_model.specification_version(), "v4")
  assert_eq(language_model.provider(), "local.chat")
  assert_eq(language_model.model_id(), "chat-model")
  let completion_model = provider.completionModel("completion-model")
  assert_eq(completion_model.specification_version(), "v4")
  assert_eq(completion_model.provider(), "local.completion")
  assert_eq(completion_model.model_id(), "completion-model")
  let embedding_model = generic_provider.embedding_model("embedding-model")
  assert_eq(embedding_model.specification_version(), "v4")
  assert_eq(embedding_model.provider(), "local.embedding")
  assert_eq(embedding_model.model_id(), "embedding-model")
  let image_model = generic_provider.image_model("image-model")
  assert_eq(image_model.specification_version(), "v4")
  assert_eq(image_model.provider(), "local.image")
  assert_eq(image_model.model_id(), "image-model")
  assert_true(generic_provider.reranking_model("missing") is None)
  assert_true(generic_provider.speech_model("missing") is None)
  assert_true(generic_provider.transcription_model("missing") is None)
  assert_true(generic_provider.files() is None)
  assert_true(generic_provider.skills() is None)
}

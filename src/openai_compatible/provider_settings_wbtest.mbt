///|
test "provider settings propagate to every compatible model" {
  let provider = create_openai_compatible(
    provider_name="local-test",
    base_url="https://example.com/v1",
    query_params={ "api-version": "2026-08" },
    supports_structured_outputs=true,
  )
  let chat = provider.chat_model_wire("chat-model")
  let completion = provider.completion_model_wire("completion-model")
  let embedding = provider.embedding_model("embedding-model")
  let image = provider.image_model("image-model")
  assert_eq(
    chat.chat_completions_url(),
    "https://example.com/v1/chat/completions?api-version=2026-08",
  )
  assert_true(chat.supports_structured_outputs)
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
  let model = provider.chat_model_wire("chat-model")
  json_inspect((model.transform_request_body)({ "model": "chat-model" }), content={
    "model": "chat-model",
    "proxy_mode": true,
  })
}

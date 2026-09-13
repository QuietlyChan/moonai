///|
test "gateway provider exposes routed language models" {
  let provider = create_gateway(api_key="gw-test")
  let model = provider.language_model("openai/gpt-5.2")
  assert_eq(model.provider(), "gateway")
  assert_eq(model.model_id(), "openai/gpt-5.2")
  assert_eq(model.specification_version(), "v4")
}

///|
test "gateway direct factory builds the same language model boundary" {
  let model = gateway("anthropic/claude-sonnet-4.5", api_key="gw-test")
  assert_eq(model.provider(), "gateway")
  assert_eq(model.model_id(), "anthropic/claude-sonnet-4.5")
}

///|
test "gateway provider exposes embedding and reranking models" {
  let provider = create_gateway(api_key="gw-test")
  let embedding = provider.embedding("openai/text-embedding-3-large")
  assert_eq(embedding.provider(), "gateway")
  assert_eq(embedding.model_id(), "openai/text-embedding-3-large")
  assert_eq(embedding.max_embeddings_per_call(), Some(2048))
  assert_true(embedding.supports_parallel_calls())
  let reranking = provider.reranking("cohere/rerank-v3.5")
  assert_eq(reranking.provider(), "gateway")
  assert_eq(reranking.model_id(), "cohere/rerank-v3.5")
}

///|
test "gateway provider exposes image models" {
  let provider = create_gateway(api_key="gw-test")
  let image = provider.image("openai/gpt-image-2")
  assert_eq(image.provider(), "gateway")
  assert_eq(image.model_id(), "openai/gpt-image-2")
  assert_eq(image.max_images_per_call(), None)
}

///|
test "perplexity provider exposes chat and embedding models" {
  let provider = create_perplexity(api_key="pplx-test")
  let chat = provider.chat("sonar-pro")
  assert_eq(chat.provider(), "perplexity")
  assert_eq(chat.model_id(), "sonar-pro")
  assert_eq(chat.specification_version(), "v4")
  let embedding = provider.embedding("pplx-embed-v1")
  assert_eq(embedding.provider(), "perplexity.embedding")
  assert_eq(embedding.max_embeddings_per_call(), Some(512))
  assert_true(embedding.supports_parallel_calls())
}

///|
test "perplexity direct factory builds the same language model boundary" {
  let model = perplexity("sonar", api_key="pplx-test")
  assert_eq(model.provider(), "perplexity")
  assert_eq(model.model_id(), "sonar")
}

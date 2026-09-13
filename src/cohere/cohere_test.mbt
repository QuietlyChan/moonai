///|
test "cohere provider exposes chat, embedding, reranking" {
  let provider = create_cohere(api_key="sk-test")
  let chat = provider.chat("command-a-03-2025")
  assert_eq(chat.provider(), "cohere.chat")
  assert_eq(chat.model_id(), "command-a-03-2025")
  let embedding = provider.embedding("embed-v4.0")
  assert_eq(embedding.provider(), "cohere.textEmbedding")
  assert_eq(embedding.max_embeddings_per_call(), Some(96))
  let reranking = provider.reranking("rerank-v3.5")
  assert_eq(reranking.provider(), "cohere.reranking")
}

///|
test "cohere direct factory builds the same language model boundary" {
  let model = cohere("command-r7b-12-2024", api_key="sk-test")
  assert_eq(model.provider(), "cohere.chat")
  assert_eq(model.model_id(), "command-r7b-12-2024")
}

///|
test "google provider exposes chat and embedding models" {
  let provider = create_google(api_key="g-test")
  let chat = provider.chat("gemini-2.5-flash")
  assert_eq(chat.provider(), "google.chat")
  assert_eq(chat.model_id(), "gemini-2.5-flash")
  assert_eq(chat.specification_version(), "v4")
  let embedding = provider.embedding("gemini-embedding-001")
  assert_eq(embedding.provider(), "google.textEmbedding")
  assert_eq(embedding.max_embeddings_per_call(), Some(100))
}

///|
test "google direct factory builds the same language model boundary" {
  let model = google("gemini-2.5-pro", api_key="g-test")
  assert_eq(model.provider(), "google.chat")
  assert_eq(model.model_id(), "gemini-2.5-pro")
}

///|
test "google provider exposes image generation models" {
  let provider = create_google(api_key="g-test")
  let image = provider.image("gemini-2.5-flash-image")
  assert_eq(image.provider(), "google.image")
  assert_eq(image.model_id(), "gemini-2.5-flash-image")
}

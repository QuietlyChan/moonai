///|
test "mistral provider exposes chat, embedding, speech, transcription" {
  let provider = create_mistral(api_key="sk-test")
  let chat = provider.chat("mistral-large-latest")
  assert_eq(chat.provider(), "mistral.chat")
  assert_eq(chat.model_id(), "mistral-large-latest")
  let embedding = provider.embedding("mistral-embed")
  assert_eq(embedding.provider(), "mistral.embedding")
  assert_eq(embedding.max_embeddings_per_call(), Some(1))
  let speech = provider.speech("voxtral-tts")
  assert_eq(speech.provider(), "mistral.speech")
  let transcription = provider.transcription("voxtral-small-latest")
  assert_eq(transcription.provider(), "mistral.transcription")
}

///|
test "mistral direct factory builds the same language model boundary" {
  let model = mistral("magistral-medium-latest", api_key="sk-test")
  assert_eq(model.provider(), "mistral.chat")
  assert_eq(model.model_id(), "magistral-medium-latest")
}

///|
test "deepinfra provider exposes chat, completion, embedding, image" {
  let provider = create_deepinfra(api_key="sk-test")
  let chat = provider.chat("meta-llama/Llama-3.3-70B-Instruct-Turbo")
  assert_eq(chat.provider(), "deepinfra.chat")
  assert_eq(chat.model_id(), "meta-llama/Llama-3.3-70B-Instruct-Turbo")
  let completion = provider.completion_model("meta-llama/Llama-2-70b-hf")
  assert_eq(completion.provider(), "deepinfra.completion")
  let embedding = provider.embedding("BAAI/bge-large-en-v1.5")
  assert_eq(embedding.provider(), "deepinfra.embedding")
  let image = provider.image("black-forest-labs/FLUX.1-schnell")
  assert_eq(image.provider(), "deepinfra.image")
  assert_eq(image.max_images_per_call(), Some(1))
}

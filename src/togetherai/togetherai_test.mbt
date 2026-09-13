///|
test "togetherai provider exposes chat, completion, embedding, image, reranking" {
  let provider = create_togetherai(api_key="sk-test")
  let chat = provider.chat("meta-llama/Llama-3.3-70B-Instruct-Turbo")
  assert_eq(chat.provider(), "togetherai.chat")
  assert_eq(chat.model_id(), "meta-llama/Llama-3.3-70B-Instruct-Turbo")
  let completion = provider.completion_model("meta-llama/Llama-2-70b-hf")
  assert_eq(completion.provider(), "togetherai.completion")
  let embedding = provider.embedding("BAAI/bge-large-en-v1.5")
  assert_eq(embedding.provider(), "togetherai.embedding")
  let image = provider.image("black-forest-labs/FLUX.1-schnell")
  assert_eq(image.provider(), "togetherai.image")
  assert_eq(image.max_images_per_call(), Some(1))
  let reranking = provider.reranking("Salesforce/Llama-Rank-v1")
  assert_eq(reranking.provider(), "togetherai.reranking")
}

///|
test "togetherai structured output support follows the upstream whitelist" {
  assert_false(
    get_model_structured_output_support(
      "meta-llama/Llama-3.3-70B-Instruct-Turbo",
    ),
  )
  assert_true(
    get_model_structured_output_support("deepseek-ai/DeepSeek-V4-Flash-0731"),
  )
}

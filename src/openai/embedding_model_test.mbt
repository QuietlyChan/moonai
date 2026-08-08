///|
async test "OpenAI embedding rejects a direct call above its batch limit" {
  let values : Array[String] = []
  for index = 0; index < 2049; index = index + 1 {
    values.push("value-{index}")
  }
  let model = create_openai(api_key="unused").embedding(
    "text-embedding-3-small",
  )
  try model.do_embed(@provider.EmbeddingModelV4CallOptions::new(values)) catch {
    @provider.TooManyEmbeddingValuesForCallError(
      provider~,
      model_id~,
      max_embeddings_per_call~,
      values=provided_values
    ) => {
      assert_eq(provider, "openai.embedding")
      assert_eq(model_id, "text-embedding-3-small")
      assert_eq(max_embeddings_per_call, 2048)
      assert_eq(provided_values.length(), 2049)
    }
    error => fail("unexpected embedding limit error: \{error}")
  } noraise {
    _ => fail("expected the direct embedding call to reject its batch")
  }
}

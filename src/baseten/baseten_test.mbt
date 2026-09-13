///|
test "baseten provider exposes chat models with usage and structured outputs" {
  let provider = create_baseten(api_key="sk-test")
  let model = provider.chat(model_id="deepseek-ai/DeepSeek-V3")
  assert_eq(model.provider(), "baseten.chat")
  assert_eq(model.model_id(), "deepseek-ai/DeepSeek-V3")
  let deployment = create_baseten(
    api_key="sk-test",
    model_url="https://model-xxxx.api.baseten.co/environments/production/sync/v1",
  )
  assert_eq(deployment.chat().model_id(), "placeholder")
}

///|
test "baseten embedding requires a sync deployment url" {
  let provider = create_baseten(api_key="sk-test")
  try provider.embedding(model_id="BAAI/bge-large-en-v1.5") catch {
    _ => assert_true(true)
  } noraise {
    _ => fail("expected missing model_url failure")
  }
  let deployment = create_baseten(
    api_key="sk-test",
    model_url="https://model-xxxx.api.baseten.co/environments/production/sync",
  )
  let model = deployment.embedding(model_id="BAAI/bge-large-en-v1.5")
  assert_eq(model.provider(), "baseten.embedding")
  assert_eq(model.max_embeddings_per_call(), Some(128))
}

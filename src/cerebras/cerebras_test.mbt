///|
test "cerebras provider exposes chat models under the cerebras.chat name" {
  let provider = create_cerebras(api_key="sk-test")
  let model = provider.chat("gpt-oss-120b")
  assert_eq(model.provider(), "cerebras.chat")
  assert_eq(model.model_id(), "gpt-oss-120b")
  assert_eq(model.specification_version(), "v4")
}

///|
test "cerebras direct factory builds the same language model boundary" {
  let model = cerebras("gemma-4-31b", api_key="sk-test")
  assert_eq(model.provider(), "cerebras.chat")
  assert_eq(model.model_id(), "gemma-4-31b")
}

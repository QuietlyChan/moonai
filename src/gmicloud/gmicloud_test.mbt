///|
test "gmicloud provider exposes chat models under the gmicloud.chat name" {
  let provider = create_gmicloud(api_key="sk-test")
  let model = provider.chat("meta-llama/Llama-3.3-70B-Instruct")
  assert_eq(model.provider(), "gmicloud.chat")
  assert_eq(model.model_id(), "meta-llama/Llama-3.3-70B-Instruct")
  assert_eq(model.specification_version(), "v4")
}

///|
test "gmicloud direct factory builds the same language model boundary" {
  let model = gmicloud("deepseek-ai/DeepSeek-V3", api_key="sk-test")
  assert_eq(model.provider(), "gmicloud.chat")
  assert_eq(model.model_id(), "deepseek-ai/DeepSeek-V3")
}

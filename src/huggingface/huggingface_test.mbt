///|
test "huggingface provider exposes responses models under huggingface.responses" {
  let provider = create_huggingface(api_key="hf-test")
  let model = provider.responses("deepseek-ai/DeepSeek-V3-0324")
  assert_eq(model.provider(), "huggingface.responses")
  assert_eq(model.model_id(), "deepseek-ai/DeepSeek-V3-0324")
  assert_eq(model.specification_version(), "v4")
}

///|
test "huggingface direct factory builds the same language model boundary" {
  let model = huggingface(
    "meta-llama/Llama-3.3-70B-Instruct",
    api_key="hf-test",
  )
  assert_eq(model.provider(), "huggingface.responses")
  assert_eq(model.model_id(), "meta-llama/Llama-3.3-70B-Instruct")
}

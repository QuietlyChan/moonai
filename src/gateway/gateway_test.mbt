///|
test "gateway provider exposes routed language models" {
  let provider = create_gateway(api_key="gw-test")
  let model = provider.language_model("openai/gpt-5.2")
  assert_eq(model.provider(), "gateway")
  assert_eq(model.model_id(), "openai/gpt-5.2")
  assert_eq(model.specification_version(), "v4")
}

///|
test "gateway direct factory builds the same language model boundary" {
  let model = gateway("anthropic/claude-sonnet-4.5", api_key="gw-test")
  assert_eq(model.provider(), "gateway")
  assert_eq(model.model_id(), "anthropic/claude-sonnet-4.5")
}

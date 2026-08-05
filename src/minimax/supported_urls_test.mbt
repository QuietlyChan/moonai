///|
test "MiniMax overrides Anthropic-compatible URL support to empty" {
  let model = minimax("MiniMax-M2.1", api_key="test-key")
  assert_eq(model.supported_urls().length(), 0)
}

///|
test "DeepSeek does not declare native URL support" {
  let model = deepseek("deepseek-chat")
  assert_eq(model.supported_urls().length(), 0)
}

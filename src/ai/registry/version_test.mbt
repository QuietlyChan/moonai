///|
test "provider packages expose the Moonai package version" {
  assert_eq(@open_responses.VERSION, "0.1.0")
  assert_eq(@openai.VERSION, "0.1.0")
  assert_eq(@openai_compatible.VERSION, "0.1.0")
  assert_eq(@anthropic.VERSION, "0.1.0")
  assert_eq(@alibaba.VERSION, "0.1.0")
  assert_eq(@deepseek.VERSION, "0.1.0")
  assert_eq(@minimax.VERSION, "0.1.0")
}

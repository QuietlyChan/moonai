///|
test "Moonshot AI detects model families" {
  assert_eq(getMoonshotAIModelFamily("kimi-k2.5"), "kimi-k2.5")
  assert_eq(getMoonshotAIModelFamily("kimi-k2.6"), "kimi-k2.6")
  assert_eq(getMoonshotAIModelFamily("kimi-k2.7-code"), "kimi-k2.7")
  assert_eq(getMoonshotAIModelFamily("kimi-k2.7-code-highspeed"), "kimi-k2.7")
  assert_eq(getMoonshotAIModelFamily("kimi-k3"), "kimi-k3")
  assert_eq(getMoonshotAIModelFamily("moonshot-v1-128k"), "moonshot-v1")
  assert_eq(getMoonshotAIModelFamily("custom-model"), "unknown")
  assert_true(is_moonshot_ai_kimi_model("kimi-k2.6"))
  assert_true(!is_moonshot_ai_kimi_model("moonshot-v1-8k"))
}

///|
test "Moonshot AI structured output support includes moonshot-v1 (#19583)" {
  assert_true(get_model_structured_output_support("moonshot-v1-8k"))
  assert_true(get_model_structured_output_support("moonshot-v1-128k"))
  assert_true(get_model_structured_output_support("moonshot-v1-auto"))
  assert_true(
    get_model_structured_output_support("moonshot-v1-32k-vision-preview"),
  )
  assert_true(get_model_structured_output_support("kimi-k2.5"))
  assert_true(!get_model_structured_output_support("moonshot-v1-lite"))
}

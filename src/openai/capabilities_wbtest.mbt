///|
test "OpenAI capability resolver identifies reasoning model families" {
  let o1 = get_openai_language_model_capabilities("o1")
  assert_eq(o1.is_reasoning_model, true)
  assert_eq(o1.system_message_mode, "developer")
  assert_eq(o1.supports_flex_processing, false)
  assert_eq(o1.supports_priority_processing, false)
  let o3 = get_openai_language_model_capabilities("o3-mini")
  assert_eq(o3.supports_flex_processing, true)
  assert_eq(o3.supports_priority_processing, true)
  let gpt51 = get_openai_language_model_capabilities("gpt-5.1")
  assert_eq(gpt51.is_reasoning_model, true)
  assert_eq(gpt51.supports_non_reasoning_parameters, true)
}

///|
test "OpenAI capability resolver keeps chat and custom IDs conservative" {
  let chat = get_openai_language_model_capabilities("gpt-5-chat-latest")
  assert_eq(chat.is_reasoning_model, false)
  assert_eq(chat.supports_flex_processing, false)
  let nano = get_openai_language_model_capabilities("gpt-5-nano")
  assert_eq(nano.supports_priority_processing, false)
  let custom = get_openai_language_model_capabilities("custom-gpt-5")
  assert_eq(custom.is_reasoning_model, false)
  assert_eq(custom.system_message_mode, "system")
}

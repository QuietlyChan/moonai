///|
test "zai provider exposes chat models under the zai.chat name" {
  let provider = create_zai(api_key="sk-test")
  let model = provider.chat("glm-5")
  assert_eq(model.provider(), "zai.chat")
  assert_eq(model.model_id(), "glm-5")
  assert_eq(model.specification_version(), "v4")
  let rules = model.supported_urls()
  assert_eq(rules.length(), 2)
  assert_true(rules[0].matches_url("https://example.com/image.png"))
  assert_true(rules[1].matches_url("https://example.com/video.mp4"))
}

///|
test "zai direct factory builds the same language model boundary" {
  let model = zai("glm-4.5v", api_key="sk-test")
  assert_eq(model.provider(), "zai.chat")
  assert_eq(model.model_id(), "glm-4.5v")
}

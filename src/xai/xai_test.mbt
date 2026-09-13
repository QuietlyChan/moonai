///|
test "xai provider exposes chat and image models" {
  let provider = create_xai(api_key="sk-test")
  let chat = provider.chat("grok-4.3")
  assert_eq(chat.provider(), "xai.chat")
  assert_eq(chat.model_id(), "grok-4.3")
  assert_eq(chat.specification_version(), "v4")
  let image = provider.image("grok-2-image-v1")
  assert_eq(image.provider(), "xai.image")
  assert_eq(image.max_images_per_call(), Some(3))
}

///|
test "xai direct factory builds the same language model boundary" {
  let model = xai("grok-4.6", api_key="sk-test")
  assert_eq(model.provider(), "xai.chat")
  assert_eq(model.model_id(), "grok-4.6")
}

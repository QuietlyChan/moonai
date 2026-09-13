///|
test "fal provider exposes image models" {
  let provider = create_fal(api_key="fal-test")
  let image = provider.image("fal-ai/flux-pro/v1.1/text-to-image")
  assert_eq(image.provider(), "fal.image")
  assert_eq(image.model_id(), "fal-ai/flux-pro/v1.1/text-to-image")
}

///|
test "fal direct factory builds the same image boundary" {
  let model = fal("fal-ai/flux/schnell", api_key="fal-test")
  assert_eq(model.provider(), "fal.image")
  assert_eq(model.model_id(), "fal-ai/flux/schnell")
}

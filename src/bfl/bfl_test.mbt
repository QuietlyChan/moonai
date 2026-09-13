///|
test "bfl provider exposes image models" {
  let provider = create_bfl(api_key="bfl-test")
  let image = provider.image("flux-pro-v1.1")
  assert_eq(image.provider(), "bfl.image")
  assert_eq(image.model_id(), "flux-pro-v1.1")
  assert_eq(image.max_images_per_call(), Some(1))
}

///|
test "bfl direct factory builds the same image boundary" {
  let model = bfl("flux-kontext-pro", api_key="bfl-test")
  assert_eq(model.provider(), "bfl.image")
  assert_eq(model.model_id(), "flux-kontext-pro")
}

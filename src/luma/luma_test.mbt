///|
test "luma provider exposes image models" {
  let provider = create_luma(api_key="lu-test")
  let image = provider.image("photon-1")
  assert_eq(image.provider(), "luma.image")
  assert_eq(image.model_id(), "photon-1")
  assert_eq(image.max_images_per_call(), Some(1))
}

///|
test "luma direct factory builds the same image boundary" {
  let model = luma("photon-flash-1", api_key="lu-test")
  assert_eq(model.provider(), "luma.image")
  assert_eq(model.model_id(), "photon-flash-1")
}

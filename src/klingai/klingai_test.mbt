///|
test "klingai provider exposes video models with the direct api key" {
  let provider = create_klingai(api_key="kl-test")
  let model = provider.video("kling-v2-master")
  assert_eq(model.provider(), "klingai.video")
  assert_eq(model.model_id(), "kling-v2-master")
  assert_eq(model.specification_version(), "v4")
}

///|
test "klingai direct factory builds the same video boundary" {
  let model = klingai("kling-v2-master", api_key="kl-test")
  assert_eq(model.provider(), "klingai.video")
}

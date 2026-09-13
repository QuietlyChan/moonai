///|
test "prodia provider exposes image and video models" {
  let provider = create_prodia(api_key="pr-test")
  let image = provider.image("flux_dev_v1p1")
  assert_eq(image.provider(), "prodia")
  assert_eq(image.model_id(), "flux_dev_v1p1")
  assert_eq(image.max_images_per_call(), Some(1))
  let video = provider.video("prodia_video_v1")
  assert_eq(video.provider(), "prodia.video")
}

///|
test "prodia direct factory builds the same image boundary" {
  let model = prodia("sd3.5_large", api_key="pr-test")
  assert_eq(model.provider(), "prodia")
  assert_eq(model.model_id(), "sd3.5_large")
}

///|
test "prodia provider exposes language models" {
  let provider = create_prodia(api_key="pr-test")
  let lm = provider.language_model("prodia-llama-4")
  assert_eq(lm.provider(), "prodia")
  assert_eq(lm.model_id(), "prodia-llama-4")
}

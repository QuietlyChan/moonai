///|
test "fal image body picks single or multi image fields" {
  let single = fal_image_request_body(
    prompt="a falcon",
    n=1,
    aspect_ratio=Some("1:1"),
    image_urls=["data:image/png;base64,AA=="],
    provider_options=Map([("guidance_scale", Json::number(3.5))]),
  )
  assert_true(
    single
    is {
      "prompt": "a falcon",
      "aspect_ratio": "1:1",
      "image_url": "data:image/png;base64,AA==",
      "guidance_scale": 3.5,
      ..
    },
  )
  let multi = fal_image_request_body(
    prompt="a falcon",
    n=1,
    aspect_ratio=None,
    image_urls=["a", "b"],
    provider_options=Map([]),
  )
  assert_true(multi is { "image_urls": ["a", "b"], .. })
  let count = fal_image_request_body(
    prompt="x",
    n=3,
    aspect_ratio=None,
    image_urls=[],
    provider_options=Map([]),
  )
  assert_true(count is { "num_images": 3, .. })
}

///|
test "fal image response decode maps urls" {
  let images = decode_fal_image_response({
    "images": [{ "url": "https://img/1.png" }, { "url": "https://img/2.png" }],
  })
  assert_eq(images.length(), 2)
  assert_eq(images[0].data, @provider.ImageData::Url("https://img/1.png"))
}

///|
test "fal error message flattens validation detail arrays" {
  assert_eq(
    fal_error_to_message({
      "detail": [{ "msg": "field required" }, { "msg": "bad value" }],
    }),
    Some("field required; bad value; "),
  )
}

///|
test "deepinfra usage fix adds excluded reasoning tokens" {
  let raw : Json = {
    "prompt_tokens": 10,
    "completion_tokens": 84,
    "total_tokens": 1094,
    "completion_tokens_details": { "reasoning_tokens": 1081 },
  }
  let fixed = deepinfra_fix_usage_raw(raw)
  assert_true(
    fixed
    is Some(
      {
        "prompt_tokens": 10,
        "completion_tokens": 1165,
        "total_tokens": 2175,
        ..
      }
    ),
  )
}

///|
test "deepinfra usage fix is a no-op for spec-compliant payloads" {
  let raw : Json = {
    "completion_tokens": 1200,
    "completion_tokens_details": { "reasoning_tokens": 1081 },
  }
  assert_eq(deepinfra_fix_usage_raw(raw), None)
  assert_eq(deepinfra_fix_usage_raw({ "completion_tokens": 5 }), None)
}

///|
test "deepinfra image body maps size and aspect ratio" {
  let body = deepinfra_image_request_body(
    prompt=Some("a red apple"),
    n=2,
    aspect_ratio=Some("1:1"),
    size=Some("1024x768"),
    seed=Some(3),
    provider_options=Map([("negative_prompt", Json::string("blurry"))]),
  )
  assert_true(
    body
    is {
      "prompt": "a red apple",
      "num_images": 2,
      "aspect_ratio": "1:1",
      "width": "1024",
      "height": "768",
      "seed": 3,
      "negative_prompt": "blurry",
      ..
    },
  )
}

///|
test "deepinfra strips data uri prefixes from image payloads" {
  assert_eq(
    deepinfra_strip_data_uri_prefix("data:image/png;base64,aGVsbG8="),
    "aGVsbG8=",
  )
  assert_eq(deepinfra_strip_data_uri_prefix("aGVsbG8="), "aGVsbG8=")
}

///|
test "deepinfra image response decode strips data uri prefixes" {
  let images = decode_deepinfra_image_response({
    "images": ["data:image/png;base64,aGVsbG8=", "dw=="],
  })
  assert_eq(images.length(), 2)
  assert_eq(images[0].data, @provider.ImageData::Base64("aGVsbG8="))
  assert_eq(images[1].data, @provider.ImageData::Base64("dw=="))
}

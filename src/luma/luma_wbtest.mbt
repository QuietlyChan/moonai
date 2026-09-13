///|
test "luma image body maps prompt model and aspect ratio" {
  let body = luma_image_request_body(
    model_id="photon-1",
    prompt="a neon city",
    aspect_ratio=Some("16:9"),
    provider_options=Map([("image_reference", Json::array([]))]),
  )
  assert_true(
    body
    is {
      "prompt": "a neon city",
      "model": "photon-1",
      "aspect_ratio": "16:9",
      "image_reference": [],
      ..
    },
  )
}

///|
test "luma status decode reads state and assets" {
  assert_eq(
    decode_luma_generation_status({
      "state": "completed",
      "assets": { "image": "https://x/1.png" },
    }),
    ("completed", Some("https://x/1.png")),
  )
  assert_eq(
    decode_luma_generation_status({ "state": "dreaming" }),
    ("dreaming", None),
  )
  assert_eq(decode_luma_generation_id({ "id": "gen-1" }), "gen-1")
}

///|
test "luma error message resolves failure reason" {
  assert_eq(
    luma_error_to_message({ "failure_reason": "policy" }),
    Some("policy"),
  )
}

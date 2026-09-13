///|
test "bfl image body maps prompt aspect ratio and seed" {
  let body = bfl_image_request_body(
    prompt="a red fox",
    n=1,
    aspect_ratio=Some("16:9"),
    seed=Some(7),
    provider_options=Map([("width", Json::number(1024))]),
  )
  assert_true(
    body
    is {
      "prompt": "a red fox",
      "aspect_ratio": "16:9",
      "seed": 7,
      "width": 1024,
      ..
    },
  )
}

///|
test "bfl poll decode reads status and sample" {
  assert_eq(
    decode_bfl_poll({
      "status": "Ready",
      "result": { "sample": "https://x/1.png" },
    }),
    ("Ready", Some("https://x/1.png")),
  )
  assert_eq(decode_bfl_poll({ "status": "Pending" }), ("Pending", None))
  assert_eq(decode_bfl_submit({ "id": "job-1" }), "job-1")
}

///|
test "bfl error message resolves detail payloads" {
  assert_eq(
    bfl_error_to_message({ "detail": "invalid prompt" }),
    Some("invalid prompt"),
  )
}

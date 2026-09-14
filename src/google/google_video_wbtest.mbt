///|
test "google video body nests instances and parameters" {
  let body = google_video_request_body(
    prompt=Some("a timelapse"),
    n=1,
    aspect_ratio=Some("16:9"),
    provider_options=Map([("durationSeconds", Json::number(8))]),
  )
  assert_true(
    body
    is {
      "instances": [{ "prompt": "a timelapse", .. }],
      "parameters": {
        "sampleCount": 1,
        "aspectRatio": "16:9",
        "durationSeconds": 8,
        ..
      },
      ..
    },
  )
}

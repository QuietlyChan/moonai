///|
test "klingai endpoint selection follows the input shape" {
  let base = @provider.VideoModelV4CallOptions::new()
  assert_eq(klingai_video_endpoint(base), "/v1/videos/text2video")
  let with_image = @provider.VideoModelV4CallOptions::new(
    image=@provider.VideoV4Url(
      url="https://example.com/a.png",
      media_type=None,
      provider_options=Map([]),
    ),
  )
  assert_eq(klingai_video_endpoint(with_image), "/v1/videos/image2video")
  let with_frames = @provider.VideoModelV4CallOptions::new(frame_images=[
    @provider.VideoModelV4FrameImage::first(
      @provider.VideoV4Url(
        url="https://example.com/f.png",
        media_type=None,
        provider_options=Map([]),
      ),
    ),
  ])
  assert_eq(klingai_video_endpoint(with_frames), "/v1/videos/multi-image2video")
}

///|
test "klingai request body nests input and maps prompt/model" {
  let options = @provider.VideoModelV4CallOptions::new(
    prompt="a cyberpunk street",
    duration=5.0,
    aspect_ratio="16:9",
  )
  let body = klingai_video_request_body(
    "kling-v2-master",
    options,
    Map([("mode", Json::string("std"))]),
  )
  assert_true(
    body
    is {
      "input": {
        "model_name": "kling-v2-master",
        "prompt": "a cyberpunk street",
        "duration": 5.0,
        "aspect_ratio": "16:9",
        "mode": "std",
        ..
      },
      ..
    },
  )
}

///|
test "klingai task status decode maps succeed and failed states" {
  let (state, videos, _) = decode_klingai_task_status({
    "data": {
      "task_status": "succeed",
      "task_result": { "videos": [{ "url": "https://v/mp4" }] },
    },
  })
  assert_eq(state, @provider.OperationSucceeded)
  assert_eq(videos.length(), 1)
  let (failed, empty, message) = decode_klingai_task_status({
    "data": { "task_status": "failed", "task_status_msg": "policy" },
  })
  assert_eq(failed, @provider.OperationFailed)
  assert_eq(empty.length(), 0)
  assert_eq(message, Some("policy"))
}

///|
test "klingai base64url escapes padding and url characters" {
  assert_eq(base64url("a+b/c=="), "a-b_c")
}

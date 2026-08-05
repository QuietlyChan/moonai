///|
test "video V4 file conversion preserves URL and inline data" {
  let url = VideoModelV4File::url(
    "https://example.com/input.mp4",
    media_type="video/mp4",
  )
  assert_true(
    url.to_video_input()
    is Url(url="https://example.com/input.mp4", media_type=Some("video/mp4")),
  )

  let bytes = VideoModelV4File::bytes(data=b"video", media_type="video/mp4")
  let wire = bytes.to_video_input()
  assert_true(
    wire is Base64(data~, media_type="video/mp4") && data == "dmlkZW8=",
  )
  assert_true(
    VideoModelV4File::from_video_input(wire)
    is VideoV4Data(
      data="dmlkZW8=",
      media_type="video/mp4",
      provider_options=options
    ) &&
    options.length() == 0,
  )
}

///|
test "video V4 result retains binary payload and diagnostics" {
  let response = VideoResponse::new([
    GeneratedVideo::new(GeneratedVideoData::Binary(b"mp4"), "video/mp4"),
  ]).with_diagnostics(
    None,
    Some(ResponseMetadata::new(model_id="mock-video")),
    Map([("mock", Json::object(Map([("ok", Json::boolean(true))])))]),
    [Warning::Other(message="one warning")],
  )
  let v4 = VideoModelV4Result::from_video_response(response)
  assert_true(
    v4.videos[0] is VideoV4Binary(data~, media_type="video/mp4") &&
    data == b"mp4",
  )
  assert_eq(v4.warnings.length(), 1)
  assert_eq(v4.response.unwrap().model_id, Some("mock-video"))
  let round_trip = v4.to_video_response()
  assert_true(
    round_trip.videos[0].data is GeneratedVideoData::Binary(data) &&
    data == b"mp4",
  )
}

///|
test "video V4 frame helpers retain semantic roles" {
  let first = VideoModelV4FrameImage::first(
    VideoModelV4File::url("https://example.com/first.png"),
  )
  let wire = first.to_video_frame()
  assert_true(wire.frame_type is FirstFrame)
  let restored = VideoModelV4FrameImage::from_video_frame_image(wire)
  assert_true(restored.frame_type is VideoV4FirstFrame)
}

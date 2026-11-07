///|
test "video V4 file conversion preserves URL and inline data" {
  let url = @provider.VideoModelV4File::url(
    "https://example.com/input.mp4",
    media_type="video/mp4",
  )
  assert_true(
    url.to_video_input()
    is Url(url="https://example.com/input.mp4", media_type=Some("video/mp4")),
  )

  let bytes = @provider.VideoModelV4File::bytes(
    data=b"video",
    media_type="video/mp4",
  )
  let wire = bytes.to_video_input()
  assert_true(
    wire is Base64(data~, media_type="video/mp4") && data == "dmlkZW8=",
  )
  assert_true(
    @provider.VideoModelV4File::from_video_input(wire)
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
  let response = @provider.VideoResponse::new([
    @provider.GeneratedVideo::new(
      @provider.GeneratedVideoData::Binary(b"mp4"),
      "video/mp4",
    ),
  ]).with_diagnostics(
    None,
    Some(@provider.ResponseMetadata::new(model_id="mock-video")),
    Map([("mock", Json::object(Map([("ok", Json::boolean(true))])))]),
    [@provider.Warning::Other(message="one warning")],
  )
  let v4 = @provider.VideoModelV4Result::from_video_response(response)
  assert_true(
    v4.videos[0] is VideoV4Binary(data~, media_type="video/mp4") &&
    data == b"mp4",
  )
  assert_eq(v4.warnings.length(), 1)
  assert_eq(v4.response.unwrap().model_id, Some("mock-video"))
  let round_trip = v4.to_video_response()
  assert_true(
    round_trip.videos[0].data is @provider.GeneratedVideoData::Binary(data) &&
    data == b"mp4",
  )
}

///|
test "video V4 frame helpers retain semantic roles" {
  let first = @provider.VideoModelV4FrameImage::first(
    @provider.VideoModelV4File::url("https://example.com/first.png"),
  )
  let wire = first.to_video_frame()
  assert_true(wire.frame_type is FirstFrame)
  let restored = @provider.VideoModelV4FrameImage::from_video_frame_image(wire)
  assert_true(restored.frame_type is VideoV4FirstFrame)
}

///|
test "legacy video options lift into V4 without losing file roles" {
  let v4 = @provider.VideoModelV4CallOptions::from_video_call_options(
    @provider.VideoCallOptions::new(
      "animate",
      image=@provider.VideoInput::base64(
        data="aW1hZ2U=",
        media_type="image/png",
      ),
      frame_images=[
        @provider.VideoFrameImage::new(
          @provider.VideoInput::url("https://example.com/last.png"),
          LastFrame,
        ),
      ],
      input_references=[
        @provider.VideoInput::url("https://example.com/ref.mp4"),
      ],
    ),
  )
  assert_eq(v4.prompt, Some("animate"))
  assert_true(v4.image is Some(VideoV4Data(data="aW1hZ2U=", ..)))
  assert_true(v4.frame_images.unwrap()[0].frame_type is VideoV4LastFrame)
  assert_true(
    v4.input_references.unwrap()[0]
    is VideoV4Url(url="https://example.com/ref.mp4", ..),
  )
}

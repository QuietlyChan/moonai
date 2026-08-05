///|
test "MiniMax video reports that one call can generate only one video" {
  let model = minimax_video("MiniMax-H3", api_key="test-key")
  let provider_options : MiniMaxVideoModelOptions = {
    resolution: None,
    ratio: None,
    reference_audio_urls: [],
    aigc_watermark: None,
    poll_interval_ms: None,
    poll_timeout_ms: None,
  }
  let warnings : Array[@provider.Warning] = []
  let _ = model.create_body(
    @provider.VideoCallOptions::new("hello", n=2),
    provider_options,
    warnings,
  )
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="n", details=_),
  )
}

///|
test "MiniMax typed video options do not serialize polling defaults" {
  json_inspect(MiniMaxVideoModelOptions::new().to_provider_options(), content={
    "minimax": Json::empty_object(),
  })
}

///|
test "typed MiniMax video options reach the H3 request body" {
  let typed = MiniMaxVideoModelOptions::new(
    resolution="2K",
    ratio="16:9",
    reference_audio_urls=["mm_file://audio-1"],
    aigc_watermark=true,
    poll_interval_ms=50,
    poll_timeout_ms=5000,
  )
  let (provider_options, parse_warnings) = parse_minimax_video_options(
    typed.to_provider_options(),
  )
  assert_eq(parse_warnings, [])
  assert_eq(provider_options.poll_interval_ms, Some(50))
  assert_eq(provider_options.poll_timeout_ms, Some(5000))
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_body(
    @provider.VideoCallOptions::new("Create a scene", input_references=[
      @provider.VideoInput::url(
        "https://example.com/reference.png",
        media_type="image/png",
      ),
    ]),
    provider_options,
    warnings,
  )
  assert_eq(warnings, [])
  assert_eq(image_count, 1)
  assert_eq(reference_videos, [])
  let text = body.stringify()
  assert_true(text.contains("\"resolution\":\"2K\""))
  assert_true(text.contains("\"ratio\":\"16:9\""))
  assert_true(text.contains("\"aigc_watermark\":true"))
  assert_true(text.contains("\"audio_url\":{\"url\":\"mm_file://audio-1\"}"))
}

///|
test "MiniMax rounds fractional duration before clamping" {
  let model = minimax_video("MiniMax-H3", api_key="test-key")
  let rounded_warnings : Array[@provider.Warning] = []
  let (rounded_body, _, _) = model.create_body(
    @provider.VideoCallOptions::new("hello", duration=7.6),
    MiniMaxVideoModelOptions::new(),
    rounded_warnings,
  )
  match rounded_body {
    { "duration": Number(value, ..), .. } => assert_eq(value, 8.0)
    _ => fail("expected a MiniMax duration")
  }
  assert_eq(rounded_warnings.length(), 1)
  match rounded_warnings[0] {
    @provider.Warning::Unsupported(feature="duration", details~) =>
      assert_true(details.contains("rounded to 8"))
    _ => fail("expected a MiniMax duration rounding warning")
  }

  let clamped_warnings : Array[@provider.Warning] = []
  let (clamped_body, _, _) = model.create_body(
    @provider.VideoCallOptions::new("hello", duration=15.6),
    MiniMaxVideoModelOptions::new(),
    clamped_warnings,
  )
  match clamped_body {
    { "duration": Number(value, ..), .. } => assert_eq(value, 15.0)
    _ => fail("expected a clamped MiniMax duration")
  }
  assert_eq(clamped_warnings.length(), 2)
  match clamped_warnings[1] {
    @provider.Warning::Unsupported(feature="duration", details~) =>
      assert_true(details.contains("clamped to 15"))
    _ => fail("expected a MiniMax duration clamp warning")
  }
}

///|
test "MiniMax resolution provider option wins with compatibility diagnostics" {
  let model = minimax_video("MiniMax-H3", api_key="test-key")
  let warnings : Array[@provider.Warning] = []
  let (body, _, _) = model.create_body(
    @provider.VideoCallOptions::new("hello", resolution="1920x1080"),
    MiniMaxVideoModelOptions::new(resolution="2K"),
    warnings,
  )
  match body {
    { "resolution": String(value), .. } => assert_eq(value, "2K")
    _ => fail("expected a MiniMax resolution")
  }
  assert_eq(warnings.length(), 1)
  match warnings[0] {
    @provider.Warning::Unsupported(feature="resolution", details~) =>
      assert_true(details.contains("providerOptions.minimax.resolution"))
    _ => fail("expected a MiniMax resolution warning")
  }

  let supported_warnings : Array[@provider.Warning] = []
  let _ = model.create_body(
    @provider.VideoCallOptions::new("hello", resolution="2048x2048"),
    MiniMaxVideoModelOptions::new(resolution="2K"),
    supported_warnings,
  )
  assert_eq(supported_warnings, [])
}

///|
test "MiniMax video rejects non-image frame inputs before encoding" {
  let model = minimax_video("MiniMax-H3", api_key="test-key")
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, _) = model.create_body(
    @provider.VideoCallOptions::new(
      "hello",
      image=@provider.VideoInput::url(
        "https://example.com/audio.mp3",
        media_type="audio/mpeg",
      ),
    ),
    MiniMaxVideoModelOptions::new(),
    warnings,
  )
  assert_eq(image_count, 0)
  assert_true(body.stringify().contains("\"content\":[{\"type\":\"text\""))
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="image", details=_),
  )

  let second_warnings : Array[@provider.Warning] = []
  let (second_body, second_count, _) = model.create_body(
    @provider.VideoCallOptions::new("hello", frame_images=[
      @provider.VideoFrameImage::new(
        @provider.VideoInput::url(
          "https://example.com/first.png",
          media_type="image/png",
        ),
        @provider.FirstFrame,
      ),
      @provider.VideoFrameImage::new(
        @provider.VideoInput::url(
          "https://example.com/doc.pdf",
          media_type="application/pdf",
        ),
        @provider.LastFrame,
      ),
    ]),
    MiniMaxVideoModelOptions::new(),
    second_warnings,
  )
  assert_eq(second_count, 1)
  assert_true(second_body.stringify().contains("first.png"))
  assert_true(!second_body.stringify().contains("doc.pdf"))
  assert_eq(second_warnings.length(), 1)
  assert_true(
    second_warnings[0]
    is @provider.Warning::Unsupported(feature="frameImages", details=_),
  )
}

///|
async test "MiniMax video preserves task usage in provider metadata" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-1\"}", "{\"task\":{\"status\":\"succeeded\",\"content\":{\"url\":\"https://example.com/video.mp4\"},\"usage\":{\"total_seconds\":5,\"input_seconds\":1,\"output_seconds\":4}}}",
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  let result = model.generate_video(
    @provider.VideoCallOptions::new(
      "hello",
      provider_options=MiniMaxVideoModelOptions::new(
        poll_interval_ms=1,
        poll_timeout_ms=10,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  match result.response {
    Some({ model_id: Some(model_id), .. }) => assert_eq(model_id, "MiniMax-H3")
    _ => fail("expected MiniMax response model metadata")
  }
  match result.provider_metadata.get("minimax") {
    Some(
      {
        "usage": {
          "totalSeconds": Number(total, ..),
          "inputSeconds": Number(input, ..),
          "outputSeconds": Number(output, ..),
          ..
        },
        ..
      }
    ) => {
      assert_eq(total.to_int(), 5)
      assert_eq(input.to_int(), 1)
      assert_eq(output.to_int(), 4)
    }
    _ => fail("expected MiniMax usage metadata")
  }
}

///|
async test "MiniMax video rejects an empty task id" {
  let transport = MiniMaxVideoProtocolTransport::new(["{\"task_id\":\"\"}"])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  try
    model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("task_id"))
      assert_true(data is { "task_id": String(""), .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an empty MiniMax task id to be rejected")
  }
}

///|
async test "MiniMax video preserves failed task diagnostics" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-failed\"}", "{\"task\":{\"status\":\"failed\",\"error\":{\"message\":\"quota exhausted\",\"code\":1008}}}",
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  try
    model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=10,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("quota exhausted"))
      assert_true(message.contains("1008"))
      assert_true(message.contains("task-failed"))
      assert_true(data is { "task": { "status": String("failed"), .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed MiniMax failed task error")
  }
}

///|
async test "MiniMax video reports cancelled tasks with their id" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-cancelled\"}", "{\"task\":{\"status\":\"cancelled\"}}",
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  try
    model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=10,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("cancelled"))
      assert_true(message.contains("task-cancelled"))
      assert_true(data is { "task": { "status": String("cancelled"), .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed MiniMax cancelled task error")
  }
}

///|
priv struct MiniMaxVideoProtocolTransport {
  responses : Array[String]
  mut next_response : Int
}

///|
fn MiniMaxVideoProtocolTransport::new(
  responses : Array[String],
) -> MiniMaxVideoProtocolTransport {
  { responses, next_response: 0 }
}

///|
impl @provider_utils.HttpTransport for MiniMaxVideoProtocolTransport with fn fetch(
  self,
  _request,
) {
  guard self.next_response < self.responses.length() else {
    fail("unexpected MiniMax video request")
  }
  let body = self.responses[self.next_response]
  self.next_response = self.next_response + 1
  @provider_utils.HttpResponse::text(status_code=200, body~)
}

///|
impl @provider_utils.HttpTransport for MiniMaxVideoProtocolTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "MiniMax video rejects a status response without task.status" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-1\"}", "{\"task\":{}}",
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  try
    model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=10,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("task.status"))
      assert_true(data is { "task": { .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed MiniMax status response error")
  }
}

///|
async test "MiniMax video exposes polling deadlines as typed timeouts" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-1\"}", "{\"task\":{\"status\":\"processing\"}}",
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  try
    model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.ProviderTimeoutError(provider~, operation~, timeout_ms~) => {
      assert_eq(provider, "minimax.video")
      assert_eq(operation, "video_generation")
      assert_eq(timeout_ms, 1)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed MiniMax video timeout")
  }
}

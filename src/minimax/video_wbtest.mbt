///|
fn minimax_video(
  model_id : MiniMaxVideoModelId,
  api_key~ : String,
  base_url? : String = "https://api.minimax.io",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> MiniMaxVideoModel {
  minimax_video_value(
    model_id,
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport=http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  )
}

///|
async fn MiniMaxVideoModel::generate_video(
  self : MiniMaxVideoModel,
  options : @provider.VideoCallOptions,
) -> @provider.VideoResponse {
  self
  .generate_video_v4(
    @provider.VideoModelV4CallOptions::from_video_call_options(options),
  )
  .to_video_response()
}

///|
fn MiniMaxVideoModel::test_create_body(
  self : MiniMaxVideoModel,
  options : @provider.VideoCallOptions,
  provider_options : MiniMaxVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> (Json, Int, Array[String]) {
  self.create_v4_body(
    @provider.VideoModelV4CallOptions::from_video_call_options(options),
    provider_options,
    warnings,
  )
}

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
  let _ = model.test_create_body(
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
  ).test_create_body(
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
test "MiniMax V4 groups image references before video references" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_v4_body(
    @provider.VideoModelV4CallOptions::new(prompt="Create a scene", input_references=[
      @provider.VideoModelV4File::url(
        "https://example.com/reference.mp4",
        media_type="video/mp4",
      ),
      @provider.VideoModelV4File::bytes(data=b"image", media_type="image/png"),
    ]),
    MiniMaxVideoModelOptions::new(),
    warnings,
  )
  assert_eq(warnings, [])
  assert_eq(image_count, 1)
  assert_eq(reference_videos, ["https://example.com/reference.mp4"])
  json_inspect(body, content={
    "model": "MiniMax-H3",
    "content": [
      { "type": "text", "text": "Create a scene" },
      {
        "type": "image_url",
        "image_url": { "url": "data:image/png;base64,aW1hZ2U=" },
        "role": "reference_image",
      },
      {
        "type": "video_url",
        "video_url": { "url": "https://example.com/reference.mp4" },
        "role": "reference_video",
      },
    ],
    "resolution": "2K",
    "duration": 5,
  })
}

///|
test "MiniMax rounds fractional duration before clamping" {
  let model = minimax_video("MiniMax-H3", api_key="test-key")
  let rounded_warnings : Array[@provider.Warning] = []
  let (rounded_body, _, _) = model.test_create_body(
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
  let (clamped_body, _, _) = model.test_create_body(
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
  let (body, _, _) = model.test_create_body(
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
  let _ = model.test_create_body(
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
  let (body, image_count, _) = model.test_create_body(
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
  let (second_body, second_count, _) = model.test_create_body(
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
        poll_timeout_ms=1000,
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
          poll_timeout_ms=1000,
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
          poll_timeout_ms=1000,
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
  responses : Array[@provider_utils.HttpResponse]
  mut next_response : Int
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn MiniMaxVideoProtocolTransport::new(
  responses : Array[String],
) -> MiniMaxVideoProtocolTransport {
  let http_responses : Array[@provider_utils.HttpResponse] = [
    for body in responses => {
      @provider_utils.HttpResponse::text(status_code=200, body~)
    }
  ]
  { responses: http_responses, next_response: 0, requests: [] }
}

///|
fn MiniMaxVideoProtocolTransport::from_http_responses(
  responses : Array[@provider_utils.HttpResponse],
) -> MiniMaxVideoProtocolTransport {
  { responses, next_response: 0, requests: [] }
}

///|
impl @provider_utils.HttpTransport for MiniMaxVideoProtocolTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  guard self.next_response < self.responses.length() else {
    fail("unexpected MiniMax video request")
  }
  let response = self.responses[self.next_response]
  self.next_response = self.next_response + 1
  response
}

///|
impl @provider_utils.HttpTransport for MiniMaxVideoProtocolTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "MiniMax video keeps polling when task.status is absent" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-1\"}", "{\"task\":{}}", "{\"task\":{\"status\":\"succeeded\",\"content\":{\"url\":\"https://example.com/video.mp4\"}}}",
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
        poll_timeout_ms=1000,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_true(
    result.videos[0].data
    is @provider.GeneratedVideoData::Url("https://example.com/video.mp4"),
  )
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
          poll_interval_ms=5,
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

///|
async test "MiniMax video V4 owns byte inputs and polling result conversion" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-v4\"}", "{\"task\":{\"status\":\"succeeded\",\"content\":{\"url\":\"https://example.com/v4.mp4\"},\"duration\":5,\"ratio\":\"16:9\",\"resolution\":\"2K\"}}",
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  let result = (model as &@provider.VideoModelV4).do_generate(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      image=@provider.VideoModelV4File::bytes(
        data=b"image",
        media_type="image/png",
      ),
      provider_options=MiniMaxVideoModelOptions::new(
        poll_interval_ms=1,
        poll_timeout_ms=1000,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_true(
    result.videos[0]
    is @provider.VideoV4Url(
      url="https://example.com/v4.mp4",
      media_type="video/mp4"
    ),
  )
  json_inspect(@json.parse(transport.requests[0].body_text()), content={
    "model": "MiniMax-H3",
    "content": [
      { "type": "text", "text": "Animate" },
      {
        "type": "image_url",
        "image_url": { "url": "data:image/png;base64,aW1hZ2U=" },
        "role": "first_frame",
      },
    ],
    "resolution": "2K",
    "duration": 5,
  })
  json_inspect(result.provider_metadata, content={
    "minimax": {
      "taskId": "task-v4",
      "videoUrl": "https://example.com/v4.mp4",
      "resolvedInputs": { "imageCount": 1, "referenceVideoUrls": [] },
      "duration": 5,
      "ratio": "16:9",
      "resolution": "2K",
    },
  })
  assert_eq(result.response.unwrap().model_id, Some("MiniMax-H3"))
  assert_true(result.response.unwrap().created_at is Some(_))
}

///|
async test "MiniMax video uses the AI SDK error-envelope fallback" {
  let transport = MiniMaxVideoProtocolTransport::from_http_responses([
    @provider_utils.HttpResponse::text(
      status_code=401,
      body="{\"type\":\"error\",\"request_id\":\"req-err-002\"}",
    ),
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
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.APICallError(message~, status_code~, url~, ..) => {
      assert_eq(message, "MiniMax video generation error")
      assert_eq(status_code, Some(401))
      assert_eq(url, "https://mock.minimax.test/v2/video_generation")
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a MiniMax API call error")
  }
}

///|
async test "MiniMax video surfaces poll errors from the provider envelope" {
  let transport = MiniMaxVideoProtocolTransport::from_http_responses([
    @provider_utils.HttpResponse::text(
      status_code=200,
      body="{\"task_id\":\"task-poll-error\"}",
    ),
    @provider_utils.HttpResponse::text(
      status_code=500,
      body="{\"error\":{\"message\":\"internal server error\"}}",
    ),
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
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.APICallError(message~, status_code~, url~, ..) => {
      assert_eq(message, "internal server error")
      assert_eq(status_code, Some(500))
      assert_eq(
        url, "https://mock.minimax.test/v2/query/video_generation/task-poll-error",
      )
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a MiniMax poll API call error")
  }
}

///|
async test "MiniMax video keeps final poll metadata and request headers" {
  let transport = MiniMaxVideoProtocolTransport::from_http_responses([
    @provider_utils.HttpResponse::text(
      status_code=200,
      body="{\"task_id\":\"task-headers\"}",
      headers={ "x-create-request-id": "create-1" },
    ),
    @provider_utils.HttpResponse::text(
      status_code=200,
      body="{\"task\":{\"status\":\"succeeded\",\"content\":{\"url\":\"https://example.com/video.mp4\"}}}",
      headers={ "x-minimax-request-id": "poll-1" },
    ),
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    headers={ "x-configured": "configured" },
    http_transport=transport,
  )
  let result = model.generate_video(
    @provider.VideoCallOptions::new(
      "hello",
      headers={
        "Authorization": "Bearer override-key",
        "x-request-header": "request-value",
      },
      provider_options=MiniMaxVideoModelOptions::new(
        poll_interval_ms=1,
        poll_timeout_ms=1000,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_eq(transport.requests.length(), 2)
  for request in transport.requests {
    assert_eq(request.headers.get("Authorization"), Some("Bearer override-key"))
    assert_eq(request.headers.get("x-configured"), Some("configured"))
    assert_eq(request.headers.get("x-request-header"), Some("request-value"))
  }
  let response = result.response.unwrap()
  assert_eq(response.headers.get("x-minimax-request-id"), Some("poll-1"))
  assert_eq(response.headers.get("x-create-request-id"), None)
}

///|
async test "MiniMax video reports missing task and video identifiers" {
  let missing_task_transport = MiniMaxVideoProtocolTransport::new(["{}"])
  let missing_task_model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=missing_task_transport,
  )
  try
    missing_task_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_eq(
        message, "No task_id returned from the MiniMax API. Response: {}",
      )
      assert_true(data is { .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a missing MiniMax task id error")
  }

  let missing_video_transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-no-video\"}", "{\"task\":{\"status\":\"succeeded\",\"content\":{}}}",
  ])
  let missing_video_model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=missing_video_transport,
  )
  try
    missing_video_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_eq(
        message, "MiniMax video generation completed but no video URL was returned. Task ID: task-no-video",
      )
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a missing MiniMax video URL error")
  }
}

///|
test "MiniMax video maps common controls and reports unsupported options" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="hello",
      n=2,
      aspect_ratio="5:4",
      resolution="2k",
      duration=3.2,
      fps=24,
      seed=7,
      generate_audio=false,
    ),
    MiniMaxVideoModelOptions::new(aigc_watermark=false),
    warnings,
  )
  json_inspect(body, content={
    "model": "MiniMax-H3",
    "content": [{ "type": "text", "text": "hello" }],
    "resolution": "2K",
    "duration": 5,
    "aigc_watermark": false,
  })
  assert_eq(image_count, 0)
  assert_eq(reference_videos, [])
  assert_eq(warnings.length(), 7)
  assert_true(warnings[0] is @provider.Warning::Unsupported(feature="fps", ..))
  assert_true(warnings[1] is @provider.Warning::Unsupported(feature="seed", ..))
  assert_true(warnings[2] is @provider.Warning::Unsupported(feature="n", ..))
  assert_true(
    warnings[3] is @provider.Warning::Unsupported(feature="generateAudio", ..),
  )
  assert_true(
    warnings[4] is @provider.Warning::Unsupported(feature="aspectRatio", ..),
  )
  assert_true(
    warnings[5] is @provider.Warning::Unsupported(feature="duration", ..),
  )
  assert_true(
    warnings[6] is @provider.Warning::Unsupported(feature="duration", ..),
  )
}

///|
test "MiniMax video routes untyped URL references and rejects other media" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_v4_body(
    @provider.VideoModelV4CallOptions::new(prompt="Animate", input_references=[
      @provider.VideoModelV4File::url(
        "https://example.com/untyped-reference.png",
      ),
      @provider.VideoModelV4File::url(
        "https://example.com/voice.mp3",
        media_type="audio/mpeg",
      ),
    ]),
    MiniMaxVideoModelOptions::new(),
    warnings,
  )
  let body_text = body.stringify()
  assert_true(body_text.contains("untyped-reference.png"))
  assert_true(!body_text.contains("voice.mp3"))
  assert_eq(image_count, 1)
  assert_eq(reference_videos, [])
  assert_eq(warnings.length(), 2)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="inputReferences", ..),
  )
  assert_true(
    warnings[1] is @provider.Warning::Unsupported(feature="inputReferences", ..),
  )
}

///|
test "MiniMax video caps reference images videos and audios" {
  let references : Array[@provider.VideoModelV4File] = []
  for index = 0; index < 10; index = index + 1 {
    references.push(
      @provider.VideoModelV4File::url(
        "https://example.com/image-\{index}.png",
        media_type="image/png",
      ),
    )
  }
  for index = 0; index < 4; index = index + 1 {
    references.push(
      @provider.VideoModelV4File::url(
        "https://example.com/video-\{index}.mp4",
        media_type="video/mp4",
      ),
    )
  }
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      input_references=references,
    ),
    MiniMaxVideoModelOptions::new(reference_audio_urls=[
      "mm_file://audio-0", "mm_file://audio-1", "mm_file://audio-2", "mm_file://audio-3",
    ]),
    warnings,
  )
  let body_text = body.stringify()
  assert_eq(image_count, 9)
  assert_eq(reference_videos, [
    "https://example.com/video-0.mp4", "https://example.com/video-1.mp4", "https://example.com/video-2.mp4",
  ])
  assert_true(body_text.contains("image-8.png"))
  assert_true(!body_text.contains("image-9.png"))
  assert_true(body_text.contains("video-2.mp4"))
  assert_true(!body_text.contains("video-3.mp4"))
  assert_true(body_text.contains("mm_file://audio-2"))
  assert_true(!body_text.contains("mm_file://audio-3"))
  assert_eq(warnings.length(), 3)
}

///|
test "MiniMax video frame mode drops references and explicit ratio" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      aspect_ratio="16:9",
      frame_images=[
        @provider.VideoModelV4FrameImage::first(
          @provider.VideoModelV4File::url("https://example.com/first.png"),
        ),
        @provider.VideoModelV4FrameImage::last(
          @provider.VideoModelV4File::url(
            "https://example.com/last.png",
            media_type="image/png",
          ),
        ),
      ],
      input_references=[
        @provider.VideoModelV4File::url(
          "https://example.com/reference.mp4",
          media_type="video/mp4",
        ),
      ],
    ),
    MiniMaxVideoModelOptions::new(reference_audio_urls=["mm_file://audio-1"]),
    warnings,
  )
  let body_text = body.stringify()
  assert_true(body_text.contains("first.png"))
  assert_true(body_text.contains("last.png"))
  assert_true(!body_text.contains("reference.mp4"))
  assert_true(!body_text.contains("mm_file://audio-1"))
  assert_true(!body_text.contains("\"ratio\""))
  assert_eq(image_count, 2)
  assert_eq(reference_videos, [])
  assert_eq(warnings.length(), 2)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="inputReferences", ..),
  )
  assert_true(
    warnings[1] is @provider.Warning::Unsupported(feature="aspectRatio", ..),
  )
}

///|
test "MiniMax invalid frame falls back to reference mode" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      aspect_ratio="16:9",
      frame_images=[
        @provider.VideoModelV4FrameImage::first(
          @provider.VideoModelV4File::url(
            "https://example.com/not-a-frame.mp4",
            media_type="video/mp4",
          ),
        ),
      ],
      input_references=[
        @provider.VideoModelV4File::url(
          "https://example.com/reference.png",
          media_type="image/png",
        ),
      ],
    ),
    MiniMaxVideoModelOptions::new(),
    warnings,
  )
  let body_text = body.stringify()
  assert_true(!body_text.contains("not-a-frame.mp4"))
  assert_true(body_text.contains("reference.png"))
  assert_true(body_text.contains("\"ratio\":\"16:9\""))
  assert_eq(image_count, 1)
  assert_eq(reference_videos, [])
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="frameImages", ..),
  )
}

///|
test "MiniMax rejects last frame without a usable first frame" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, _) = minimax_video("MiniMax-H3", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(prompt="Animate", frame_images=[
      @provider.VideoModelV4FrameImage::last(
        @provider.VideoModelV4File::url(
          "https://example.com/last.png",
          media_type="image/png",
        ),
      ),
    ]),
    MiniMaxVideoModelOptions::new(),
    warnings,
  )
  assert_true(!body.stringify().contains("last.png"))
  assert_eq(image_count, 0)
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="frameImages", ..),
  )
}

///|
async test "MiniMax video reports missing task and remaining terminal states" {
  let missing_task_transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-missing\"}", "{}",
  ])
  let missing_task_model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=missing_task_transport,
  )
  try
    missing_task_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.APICallError(
      message~,
      status_code~,
      response_body~,
      is_retryable~,
      data~,
      cause~,
      ..
    ) => {
      assert_eq(message, "Invalid JSON response")
      assert_eq(status_code, Some(200))
      assert_eq(response_body, "{}")
      assert_false(is_retryable)
      assert_true(data is Some({ .. }))
      assert_true(cause.unwrap_or("").contains("task must be an object"))
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a missing MiniMax task error")
  }

  let failed_transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-bare-failure\"}", "{\"task\":{\"status\":\"failed\"}}",
  ])
  let failed_model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=failed_transport,
  )
  try
    failed_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_eq(
        message, "MiniMax video generation failed. Task ID: task-bare-failure",
      )
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a bare MiniMax task failure")
  }

  let expired_transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-expired\"}", "{\"task\":{\"status\":\"expired\"}}",
  ])
  let expired_model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=expired_transport,
  )
  try
    expired_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) => {
      assert_true(message.contains("expired"))
      assert_true(message.contains("task-expired"))
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an expired MiniMax task error")
  }
}

///|
async test "MiniMax metadata reports only URL reference videos" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-references\"}", "{\"task\":{\"status\":\"succeeded\",\"content\":{\"url\":\"https://example.com/output.mp4\"}}}",
  ])
  let model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=transport,
  )
  let result = (model as &@provider.VideoModelV4).do_generate(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      input_references=[
        @provider.VideoModelV4File::url(
          "https://example.com/reference.mp4",
          media_type="video/mp4",
        ),
        @provider.VideoModelV4File::bytes(
          data=b"inline-video",
          media_type="video/mp4",
        ),
      ],
      provider_options=MiniMaxVideoModelOptions::new(
        poll_interval_ms=1,
        poll_timeout_ms=1000,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  json_inspect(result.provider_metadata, content={
    "minimax": {
      "taskId": "task-references",
      "videoUrl": "https://example.com/output.mp4",
      "resolvedInputs": {
        "imageCount": 0,
        "referenceVideoUrls": ["https://example.com/reference.mp4"],
      },
    },
  })
}

///|
test "MiniMax public factories expose AI SDK model contracts" {
  let provider = createMiniMax(api_key="test-key")
  let generic_provider = provider as &@provider.ProviderV4
  assert_eq(generic_provider.specification_version(), "v4")
  let language_model = provider.languageModel("MiniMax-M2.5")
  assert_eq(language_model.specification_version(), "v4")
  assert_eq(language_model.provider(), "minimax.messages")
  assert_eq(language_model.model_id(), "MiniMax-M2.5")
  let video_model = provider.videoModel("MiniMax-H3")
  assert_eq(video_model.specification_version(), "v4")
  assert_eq(video_model.provider(), "minimax.video")
  assert_eq(video_model.model_id(), "MiniMax-H3")
  assert_eq(video_model.max_videos_per_call(), Some(1))
  assert_true(generic_provider.reranking_model("missing") is None)
  assert_true(generic_provider.speech_model("missing") is None)
  assert_true(generic_provider.transcription_model("missing") is None)
  assert_true(generic_provider.files() is None)
  assert_true(generic_provider.skills() is None)
  try generic_provider.embedding_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.EmbeddingModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected MiniMax embedding model rejection")
  }
  try generic_provider.image_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.ImageModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected MiniMax image model rejection")
  }
  json_inspect(
    MiniMaxLanguageModelOptions::new(thinking=DisabledThinking).to_provider_options(),
    content={ "minimax": { "thinking": { "type": "disabled" } } },
  )
}

///|
test "MiniMax typed video options reject invalid values" {
  try MiniMaxVideoModelOptions::new(ratio="5:4") catch {
    Failure::Failure(message) => assert_true(message.contains("ratio"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected invalid MiniMax ratio rejection")
  }
  try MiniMaxVideoModelOptions::new(poll_interval_ms=0) catch {
    Failure::Failure(message) => assert_true(message.contains("poll_interval"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected invalid MiniMax poll interval rejection")
  }
  try MiniMaxVideoModelOptions::new(poll_timeout_ms=0) catch {
    Failure::Failure(message) => assert_true(message.contains("poll_timeout"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected invalid MiniMax poll timeout rejection")
  }
}

///|
test "MiniMax provider option diagnostics retain valid reference audio" {
  let (options, warnings) = parse_minimax_video_options(
    Map([
      (
        "minimax",
        { "referenceAudioUrls": ["mm_file://audio-1", 42], "pollIntervalMs": 5 },
      ),
    ]),
  )
  assert_eq(options.reference_audio_urls, ["mm_file://audio-1"])
  assert_eq(options.poll_interval_ms, Some(5))
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0]
    is @provider.Warning::Compatibility(
      feature="providerOptions.minimax.referenceAudioUrls",
      ..
    ),
  )
}

///|
test "MiniMax video rejects unsupported resolution and unpaired audio" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, reference_videos) = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
  ).create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      resolution="1920x1080",
    ),
    MiniMaxVideoModelOptions::new(reference_audio_urls=["mm_file://audio-1"]),
    warnings,
  )
  let body_text = body.stringify()
  assert_true(body_text.contains("\"resolution\":\"2K\""))
  assert_true(!body_text.contains("mm_file://audio-1"))
  assert_eq(image_count, 0)
  assert_eq(reference_videos, [])
  assert_eq(warnings.length(), 2)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="resolution", ..),
  )
  assert_true(
    warnings[1]
    is @provider.Warning::Unsupported(feature="referenceAudioUrls", ..),
  )
}

///|
test "MiniMax video rejects a video last frame" {
  let warnings : Array[@provider.Warning] = []
  let (body, image_count, _) = minimax_video("MiniMax-H3", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(prompt="Animate", frame_images=[
      @provider.VideoModelV4FrameImage::first(
        @provider.VideoModelV4File::url(
          "https://example.com/first.png",
          media_type="image/png",
        ),
      ),
      @provider.VideoModelV4FrameImage::last(
        @provider.VideoModelV4File::url(
          "https://example.com/last.mp4",
          media_type="video/mp4",
        ),
      ),
    ]),
    MiniMaxVideoModelOptions::new(),
    warnings,
  )
  let body_text = body.stringify()
  assert_true(body_text.contains("first.png"))
  assert_true(!body_text.contains("last.mp4"))
  assert_eq(image_count, 1)
  assert_eq(warnings.length(), 1)
  match warnings[0] {
    @provider.Warning::Unsupported(feature="frameImages", details~) =>
      assert_true(details.contains("last_frame video"))
    _ => fail("expected MiniMax last-frame warning")
  }
}

///|
async test "MiniMax video preserves string and numeric task error codes" {
  let transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-string-code\"}", "{\"task\":{\"status\":\"failed\",\"error\":{\"message\":\"rejected\",\"code\":\"E_POLICY\"}}}",
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
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) => {
      assert_true(message.contains("rejected"))
      assert_true(message.contains("E_POLICY"))
      assert_true(message.contains("task-string-code"))
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a MiniMax string error code")
  }

  let numeric_transport = MiniMaxVideoProtocolTransport::new([
    "{\"task_id\":\"task-numeric-code\"}", "{\"task\":{\"status\":\"failed\",\"error\":{\"code\":1008.5}}}",
  ])
  let numeric_model = minimax_video(
    "MiniMax-H3",
    api_key="test-key",
    base_url="https://mock.minimax.test",
    http_transport=numeric_transport,
  )
  try
    numeric_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=MiniMaxVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) => {
      assert_true(message.contains("1008.5"))
      assert_true(message.contains("task-numeric-code"))
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a MiniMax numeric error code")
  }
}

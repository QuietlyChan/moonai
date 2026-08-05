///|
test "Alibaba video reports that one call can generate only one video" {
  let model = alibaba_video("wan2.6-t2v", api_key="test-key")
  let provider_options : AlibabaVideoModelOptions = {
    negative_prompt: None,
    audio_url: None,
    prompt_extend: None,
    shot_type: None,
    watermark: None,
    audio: None,
    reference_urls: [],
    ratio: None,
    media: [],
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
test "Alibaba typed video options do not serialize polling defaults" {
  json_inspect(AlibabaVideoModelOptions::new().to_provider_options(), content={
    "alibaba": Json::empty_object(),
  })
}

///|
test "typed Alibaba video options reach wan2.7 request fields" {
  let typed = AlibabaVideoModelOptions::new(
    negative_prompt="blur",
    prompt_extend=true,
    watermark=true,
    ratio="16:9",
    media=[
      AlibabaVideoMedia::new(
        media_type="reference_image",
        url="https://example.com/reference.png",
        reference_voice="https://example.com/voice.mp3",
      ),
    ],
    poll_interval_ms=50,
    poll_timeout_ms=5000,
  )
  let (provider_options, parse_warnings) = parse_alibaba_video_options(
    typed.to_provider_options(),
  )
  assert_eq(parse_warnings, [])
  assert_eq(provider_options.poll_interval_ms, Some(50))
  assert_eq(provider_options.poll_timeout_ms, Some(5000))
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.7-r2v", api_key="test-key").create_body(
    @provider.VideoCallOptions::new("Create a scene", duration=5.5),
    provider_options,
    warnings,
  )
  assert_eq(warnings, [])
  json_inspect(body, content={
    "model": "wan2.7-r2v",
    "input": {
      "prompt": "Create a scene",
      "negative_prompt": "blur",
      "media": [
        {
          "type": "reference_image",
          "url": "https://example.com/reference.png",
          "reference_voice": "https://example.com/voice.mp3",
        },
      ],
    },
    "parameters": {
      "duration": 5.5,
      "ratio": "16:9",
      "prompt_extend": true,
      "watermark": true,
    },
  })
}

///|
test "Alibaba video preserves task and usage metadata" {
  let metadata = alibaba_video_task_metadata(
    "task-abc-123",
    "https://dashscope.example/video.mp4",
    { "request_id": "create-001" },
    {
      "request_id": "poll-002",
      "output": {
        "task_status": "SUCCEEDED",
        "submit_time": "2026-08-04T10:00:00Z",
        "end_time": "2026-08-04T10:00:05Z",
        "actual_prompt": "An enhanced prompt",
      },
      "usage": {
        "duration": 5.0,
        "output_video_duration": 5,
        "SR": 1080,
        "size": "1920x1080",
      },
    },
    "wan2.6-t2v",
  )
  json_inspect(metadata, content={
    "taskId": "task-abc-123",
    "videoUrl": "https://dashscope.example/video.mp4",
    "modelId": "wan2.6-t2v",
    "createRequestId": "create-001",
    "requestId": "poll-002",
    "taskStatus": "SUCCEEDED",
    "submitTime": "2026-08-04T10:00:00Z",
    "endTime": "2026-08-04T10:00:05Z",
    "actualPrompt": "An enhanced prompt",
    "usage": {
      "duration": 5.0,
      "outputVideoDuration": 5,
      "resolution": 1080,
      "size": "1920x1080",
    },
  })
}

///|
test "Alibaba I2V finds first_frame and sends raw base64" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.6-i2v", api_key="test-key").create_body(
    @provider.VideoCallOptions::new(
      "Animate",
      image=@provider.VideoInput::url(
        "https://example.com/legacy.png",
        media_type="image/png",
      ),
      frame_images=[
        @provider.VideoFrameImage::new(
          @provider.VideoInput::url(
            "https://example.com/last.png",
            media_type="image/png",
          ),
          @provider.LastFrame,
        ),
        @provider.VideoFrameImage::new(
          @provider.VideoInput::base64(data="iVBORw==", media_type="image/png"),
          @provider.FirstFrame,
        ),
      ],
    ),
    AlibabaVideoModelOptions::new(),
    warnings,
  )
  json_inspect(body, content={
    "model": "wan2.6-i2v",
    "input": { "prompt": "Animate", "img_url": "iVBORw==" },
    "parameters": Json::empty_object(),
  })
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0]
    is @provider.Warning::Unsupported(feature="frameImages", details=_),
  )
}

///|
test "Alibaba wan2.7 media accepts inline images and skips inline videos" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.7-r2v", api_key="test-key").create_body(
    @provider.VideoCallOptions::new(
      "Animate",
      frame_images=[
        @provider.VideoFrameImage::new(
          @provider.VideoInput::base64(data="Zmlyc3Q=", media_type="image/png"),
          @provider.FirstFrame,
        ),
      ],
      input_references=[
        @provider.VideoInput::base64(data="aW1hZ2U=", media_type="image/jpeg"),
        @provider.VideoInput::url("https://example.com/reference.mp4"),
        @provider.VideoInput::base64(data="dmlkZW8=", media_type="video/mp4"),
      ],
    ),
    AlibabaVideoModelOptions::new(),
    warnings,
  )
  json_inspect(body, content={
    "model": "wan2.7-r2v",
    "input": {
      "prompt": "Animate",
      "media": [
        { "type": "reference_image", "url": "data:image/jpeg;base64,aW1hZ2U=" },
        {
          "type": "reference_video",
          "url": "https://example.com/reference.mp4",
        },
        { "type": "first_frame", "url": "data:image/png;base64,Zmlyc3Q=" },
      ],
    },
    "parameters": Json::empty_object(),
  })
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0]
    is @provider.Warning::Unsupported(feature="inputReferences", details=_),
  )
}

///|
test "Alibaba wan2.6 prefers standard input references" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.6-r2v", api_key="test-key").create_body(
    @provider.VideoCallOptions::new("Animate", input_references=[
      @provider.VideoInput::url("https://example.com/standard.png"),
    ]),
    AlibabaVideoModelOptions::new(reference_urls=[
      "https://example.com/legacy.png",
    ]),
    warnings,
  )
  json_inspect(body, content={
    "model": "wan2.6-r2v",
    "input": {
      "prompt": "Animate",
      "reference_urls": ["https://example.com/standard.png"],
    },
    "parameters": Json::empty_object(),
  })
  assert_eq(warnings, [])

  let unsupported : Array[@provider.Warning] = []
  let t2v = alibaba_video("wan2.6-t2v", api_key="test-key").create_body(
    @provider.VideoCallOptions::new("Animate", input_references=[
      @provider.VideoInput::url("https://example.com/ignored.png"),
    ]),
    AlibabaVideoModelOptions::new(),
    unsupported,
  )
  assert_true(!t2v.stringify().contains("ignored.png"))
  assert_true(
    unsupported[0]
    is @provider.Warning::Unsupported(feature="inputReferences", details=_),
  )
}

///|
priv struct AlibabaVideoProtocolTransport {
  responses : Array[String]
  mut next_response : Int
}

///|
fn AlibabaVideoProtocolTransport::new(
  responses : Array[String],
) -> AlibabaVideoProtocolTransport {
  { responses, next_response: 0 }
}

///|
impl @provider_utils.HttpTransport for AlibabaVideoProtocolTransport with fn fetch(
  self,
  _request,
) {
  guard self.next_response < self.responses.length() else {
    fail("unexpected Alibaba video request")
  }
  let body = self.responses[self.next_response]
  self.next_response = self.next_response + 1
  @provider_utils.HttpResponse::text(status_code=200, body~)
}

///|
impl @provider_utils.HttpTransport for AlibabaVideoProtocolTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "Alibaba video rejects an empty task id" {
  let transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_id\":\"\"}}",
  ])
  let model = alibaba_video(
    "wan2.6-t2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
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
      assert_true(message.contains("output.task_id"))
      assert_true(data is { "output": { "task_id": String(""), .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an empty Alibaba task id to be rejected")
  }
}

///|
async test "Alibaba video rejects a status response without task_status" {
  let transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_id\":\"task-1\"}}", "{\"output\":{}}",
  ])
  let model = alibaba_video(
    "wan2.6-t2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
    http_transport=transport,
  )
  try
    model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=AlibabaVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=10,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("task_status"))
      assert_true(data is { "output": { .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed Alibaba status response error")
  }
}

///|
async test "Alibaba video exposes polling deadlines as typed timeouts" {
  let transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_id\":\"task-1\"}}", "{\"output\":{\"task_status\":\"RUNNING\"}}",
  ])
  let model = alibaba_video(
    "wan2.6-t2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
    http_transport=transport,
  )
  try
    model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=AlibabaVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.ProviderTimeoutError(provider~, operation~, timeout_ms~) => {
      assert_eq(provider, "alibaba.video")
      assert_eq(operation, "video_generation")
      assert_eq(timeout_ms, 1)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed Alibaba video timeout")
  }
}

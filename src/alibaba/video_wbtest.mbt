///|
fn alibaba_video(
  model_id : AlibabaVideoModelId,
  api_key~ : String,
  base_url? : String = "https://dashscope-intl.aliyuncs.com",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> AlibabaVideoModel {
  alibaba_video_value(
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
fn alibaba_video_legacy_options(
  options : @provider.VideoCallOptions,
) -> @provider.VideoModelV4CallOptions {
  @provider.VideoModelV4CallOptions::from_video_call_options(options)
}

///|
async fn AlibabaVideoModel::generate_video(
  self : AlibabaVideoModel,
  options : @provider.VideoCallOptions,
) -> @provider.VideoResponse {
  self
  .generate_video_v4(alibaba_video_legacy_options(options))
  .to_video_response()
}

///|
fn AlibabaVideoModel::test_create_body(
  self : AlibabaVideoModel,
  options : @provider.VideoCallOptions,
  provider_options : AlibabaVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> Json {
  self.create_v4_body(
    alibaba_video_legacy_options(options),
    provider_options,
    warnings,
  )
}

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
  let body = alibaba_video("wan2.7-r2v", api_key="test-key").test_create_body(
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
test "Alibaba wan2.7 I2V rejects unsupported resolution tiers" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.7-i2v", api_key="test-key").test_create_body(
    @provider.VideoCallOptions::new("Animate", resolution="832x480"),
    AlibabaVideoModelOptions::new(),
    warnings,
  )
  json_inspect(body, content={
    "model": "wan2.7-i2v",
    "input": { "prompt": "Animate" },
    "parameters": Json::empty_object(),
  })
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0]
    is @provider.Warning::Unsupported(feature="resolution", details=_),
  )
}

///|
test "Alibaba video preserves task and usage metadata" {
  let metadata = alibaba_video_task_metadata(
    "task-abc-123",
    "https://dashscope.example/video.mp4",
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
  )
  json_inspect(metadata, content={
    "taskId": "task-abc-123",
    "videoUrl": "https://dashscope.example/video.mp4",
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
  let body = alibaba_video("wan2.6-i2v", api_key="test-key").test_create_body(
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
  let body = alibaba_video("wan2.7-r2v", api_key="test-key").test_create_body(
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
  let body = alibaba_video("wan2.6-r2v", api_key="test-key").test_create_body(
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
  let t2v = alibaba_video("wan2.6-t2v", api_key="test-key").test_create_body(
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
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn AlibabaVideoProtocolTransport::new(
  responses : Array[String],
) -> AlibabaVideoProtocolTransport {
  { responses, next_response: 0, requests: [] }
}

///|
impl @provider_utils.HttpTransport for AlibabaVideoProtocolTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
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
          poll_timeout_ms=1_000,
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

///|
async test "Alibaba video V4 owns binary input and polling result conversion" {
  let transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_status\":\"PENDING\",\"task_id\":\"task-v4\"}}", "{\"output\":{\"task_id\":\"task-v4\",\"task_status\":\"SUCCEEDED\",\"video_url\":\"https://example.com/v4.mp4\",\"actual_prompt\":\"Enhanced\"},\"usage\":{\"duration\":5,\"output_video_duration\":5,\"SR\":1080,\"size\":\"1920x1080\"}}",
  ])
  let model = alibaba_video(
    "wan2.6-i2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
    http_transport=transport,
  )
  let result = (model as &@provider.VideoModelV4).do_generate(
    @provider.VideoModelV4CallOptions::new(
      prompt="",
      image=@provider.VideoModelV4File::bytes(
        data=b"image",
        media_type="image/png",
      ),
      provider_options=AlibabaVideoModelOptions::new(
        poll_interval_ms=1,
        poll_timeout_ms=1_000,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_eq(result.videos.length(), 1)
  assert_true(
    result.videos[0]
    is @provider.VideoV4Url(
      url="https://example.com/v4.mp4",
      media_type="video/mp4"
    ),
  )
  assert_eq(result.response.unwrap().model_id, Some("wan2.6-i2v"))
  assert_true(result.response.unwrap().created_at is Some(_))
  json_inspect(@json.parse(result.request.unwrap().body), content={
    "model": "wan2.6-i2v",
    "input": { "prompt": "", "img_url": "aW1hZ2U=" },
    "parameters": Json::empty_object(),
  })
  json_inspect(result.provider_metadata, content={
    "alibaba": {
      "taskId": "task-v4",
      "videoUrl": "https://example.com/v4.mp4",
      "actualPrompt": "Enhanced",
      "usage": {
        "duration": 5,
        "outputVideoDuration": 5,
        "resolution": 1080,
        "size": "1920x1080",
      },
    },
  })
  assert_eq(result.response.unwrap().model_id, Some("wan2.6-i2v"))
}

///|
test "Alibaba wan2.6 maps standard controls and provider options" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.6-t2v", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      n=2,
      aspect_ratio="16:9",
      resolution="1280x720",
      duration=5.5,
      fps=24,
      seed=42,
      generate_audio=false,
    ),
    AlibabaVideoModelOptions::new(
      audio_url="https://example.com/audio.mp3",
      prompt_extend=false,
      shot_type="multi",
      watermark=false,
      audio=true,
    ),
    warnings,
  )
  json_inspect(body, content={
    "model": "wan2.6-t2v",
    "input": {
      "prompt": "Animate",
      "audio_url": "https://example.com/audio.mp3",
    },
    "parameters": {
      "duration": 5.5,
      "seed": 42,
      "size": "1280*720",
      "prompt_extend": false,
      "shot_type": "multi",
      "watermark": false,
      "audio": false,
    },
  })
  assert_eq(warnings.length(), 3)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="aspectRatio", ..),
  )
  assert_true(warnings[1] is @provider.Warning::Unsupported(feature="fps", ..))
  assert_true(warnings[2] is @provider.Warning::Unsupported(feature="n", ..))
}

///|
test "Alibaba video preserves AI SDK warning order" {
  let warnings : Array[@provider.Warning] = []
  let _ = alibaba_video("wan2.7-i2v", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      n=2,
      aspect_ratio="16:9",
      resolution="832x480",
      fps=24,
      generate_audio=true,
      frame_images=[
        @provider.VideoModelV4FrameImage::new(
          @provider.VideoModelV4File::url(
            "https://example.com/last.png",
            media_type="image/png",
          ),
          @provider.VideoV4LastFrame,
        ),
      ],
      input_references=[
        @provider.VideoModelV4File::url(
          "https://example.com/reference.png",
          media_type="image/png",
        ),
      ],
    ),
    AlibabaVideoModelOptions::new(shot_type="single"),
    warnings,
  )
  assert_eq(warnings.length(), 8)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="frameImages", ..),
  )
  assert_true(
    warnings[1] is @provider.Warning::Unsupported(feature="inputReferences", ..),
  )
  assert_true(
    warnings[2] is @provider.Warning::Unsupported(feature="resolution", ..),
  )
  assert_true(
    warnings[3] is @provider.Warning::Unsupported(feature="shotType", ..),
  )
  assert_true(
    warnings[4] is @provider.Warning::Unsupported(feature="generateAudio", ..),
  )
  assert_true(
    warnings[5] is @provider.Warning::Unsupported(feature="aspectRatio", ..),
  )
  assert_true(warnings[6] is @provider.Warning::Unsupported(feature="fps", ..))
  assert_true(warnings[7] is @provider.Warning::Unsupported(feature="n", ..))
}

///|
test "Alibaba wan2.7 maps resolution ratio and removed controls" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.7-r2v", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      aspect_ratio="16:9",
      resolution="1920x1080",
      generate_audio=true,
      input_references=[
        @provider.VideoModelV4File::url(
          "https://example.com/reference.png",
          media_type="image/png",
        ),
      ],
    ),
    AlibabaVideoModelOptions::new(shot_type="single", ratio="9:16"),
    warnings,
  )
  json_inspect(body, content={
    "model": "wan2.7-r2v",
    "input": {
      "prompt": "Animate",
      "media": [
        {
          "type": "reference_image",
          "url": "https://example.com/reference.png",
        },
      ],
    },
    "parameters": { "resolution": "1080P", "ratio": "9:16" },
  })
  assert_eq(warnings.length(), 2)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="shotType", ..),
  )
  assert_true(
    warnings[1] is @provider.Warning::Unsupported(feature="generateAudio", ..),
  )

  let derived_warnings : Array[@provider.Warning] = []
  let derived = alibaba_video("wan2.7-t2v", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      resolution="1280x720",
    ),
    AlibabaVideoModelOptions::new(),
    derived_warnings,
  )
  json_inspect(derived, content={
    "model": "wan2.7-t2v",
    "input": { "prompt": "Animate" },
    "parameters": { "resolution": "720P", "ratio": "16:9" },
  })
  assert_eq(derived_warnings, [])
}

///|
test "Alibaba I2V maps URL frames and resolution tiers" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.6-i2v", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Animate",
      aspect_ratio="1:1",
      resolution="1280x720",
      image=@provider.VideoModelV4File::url(
        "https://example.com/first.png",
        media_type="image/png",
      ),
    ),
    AlibabaVideoModelOptions::new(),
    warnings,
  )
  json_inspect(body, content={
    "model": "wan2.6-i2v",
    "input": { "prompt": "Animate", "img_url": "https://example.com/first.png" },
    "parameters": { "resolution": "720P" },
  })
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="aspectRatio", ..),
  )
}

///|
test "Alibaba legacy R2V skips inline references without provider fallback" {
  let warnings : Array[@provider.Warning] = []
  let body = alibaba_video("wan2.6-r2v", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(prompt="Animate", input_references=[
      @provider.VideoModelV4File::bytes(
        data=b"reference",
        media_type="image/png",
      ),
    ]),
    AlibabaVideoModelOptions::new(reference_urls=[
      "https://example.com/provider-fallback.png",
    ]),
    warnings,
  )
  assert_true(!body.stringify().contains("reference_urls"))
  assert_true(!body.stringify().contains("provider-fallback.png"))
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0] is @provider.Warning::Unsupported(feature="inputReferences", ..),
  )

  let fallback_warnings : Array[@provider.Warning] = []
  let fallback = alibaba_video("wan2.6-r2v", api_key="test-key").create_v4_body(
    @provider.VideoModelV4CallOptions::new(prompt="Animate"),
    AlibabaVideoModelOptions::new(reference_urls=[
      "https://example.com/provider-fallback.png",
    ]),
    fallback_warnings,
  )
  assert_true(fallback.stringify().contains("provider-fallback.png"))
  assert_eq(fallback_warnings, [])
}

///|
async test "Alibaba video reports failed canceled and missing video tasks" {
  let failed_transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_id\":\"task-failed\"}}", "{\"output\":{\"task_status\":\"FAILED\",\"message\":\"policy rejected\"}}",
  ])
  let failed_model = alibaba_video(
    "wan2.6-t2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
    http_transport=failed_transport,
  )
  try
    failed_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=AlibabaVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("failed"))
      assert_true(message.contains("policy rejected"))
      assert_true(message.contains("task-failed"))
      assert_true(
        data is { "output": { "task_status": String("FAILED"), .. }, .. },
      )
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected failed Alibaba video task")
  }

  let canceled_transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_id\":\"task-canceled\"}}", "{\"output\":{\"task_status\":\"CANCELED\"}}",
  ])
  let canceled_model = alibaba_video(
    "wan2.6-t2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
    http_transport=canceled_transport,
  )
  try
    canceled_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=AlibabaVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) => {
      assert_true(message.contains("canceled"))
      assert_true(message.contains("task-canceled"))
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected canceled Alibaba video task")
  }

  let missing_video_transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_id\":\"task-no-video\"}}", "{\"output\":{\"task_status\":\"SUCCEEDED\"}}",
  ])
  let missing_video_model = alibaba_video(
    "wan2.6-t2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
    http_transport=missing_video_transport,
  )
  try
    missing_video_model.generate_video(
      @provider.VideoCallOptions::new(
        "hello",
        provider_options=AlibabaVideoModelOptions::new(
          poll_interval_ms=1,
          poll_timeout_ms=1000,
        ).to_provider_options(),
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("without a video URL"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing Alibaba video URL error")
  }
}

///|
async test "Alibaba video separates create and poll headers" {
  let transport = AlibabaVideoProtocolTransport::new([
    "{\"output\":{\"task_id\":\"task-headers\"}}", "{\"output\":{\"task_status\":\"SUCCEEDED\",\"video_url\":\"https://example.com/video.mp4\"}}",
  ])
  let model = alibaba_video(
    "wan2.6-t2v",
    api_key="test-key",
    base_url="https://mock.alibaba.test",
    headers={ "x-configured": "configured" },
    http_transport=transport,
  )
  let _ = model.generate_video(
    @provider.VideoCallOptions::new(
      "hello",
      headers={
        "Authorization": "Bearer override-key",
        "x-request-header": "request-value",
        "x-dashscope-async": "disable",
      },
      provider_options=AlibabaVideoModelOptions::new(
        poll_interval_ms=1,
        poll_timeout_ms=1000,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_eq(transport.requests.length(), 2)
  assert_eq(transport.requests[0].meth, @provider_utils.HttpPost)
  assert_eq(transport.requests[1].meth, @provider_utils.HttpGet)
  assert_eq(
    transport.requests[0].headers.get("X-DashScope-Async"),
    Some("enable"),
  )
  assert_eq(transport.requests[0].headers.get("x-dashscope-async"), None)
  assert_eq(transport.requests[1].headers.get("X-DashScope-Async"), None)
  for request in transport.requests {
    assert_eq(request.headers.get("Authorization"), Some("Bearer override-key"))
    assert_eq(request.headers.get("x-configured"), Some("configured"))
    assert_eq(request.headers.get("x-request-header"), Some("request-value"))
  }
}

///|
test "Alibaba public factories expose AI SDK model contracts" {
  let provider = createAlibaba(api_key="test-key")
  let generic_provider = provider as &@provider.ProviderV4
  assert_eq(generic_provider.specification_version(), "v4")
  let language_model = provider.languageModel("qwen-plus")
  assert_eq(language_model.specification_version(), "v4")
  assert_eq(language_model.provider(), "alibaba.chat")
  assert_eq(language_model.model_id(), "qwen-plus")
  assert_eq(provider.chatModel("qwen-plus").model_id(), "qwen-plus")
  let embedding_model = provider.embeddingModel("text-embedding-v4")
  assert_eq(embedding_model.specification_version(), "v4")
  assert_eq(embedding_model.provider(), "alibaba.embedding")
  assert_eq(embedding_model.model_id(), "text-embedding-v4")
  assert_eq(embedding_model.max_embeddings_per_call(), Some(10))
  assert_eq(embedding_model.supports_parallel_calls(), false)
  let video_model = provider.videoModel("wan2.7-t2v")
  assert_eq(video_model.specification_version(), "v4")
  assert_eq(video_model.provider(), "alibaba.video")
  assert_eq(video_model.model_id(), "wan2.7-t2v")
  assert_eq(video_model.max_videos_per_call(), Some(1))
  assert_true(generic_provider.reranking_model("missing") is None)
  assert_true(generic_provider.speech_model("missing") is None)
  assert_true(generic_provider.transcription_model("missing") is None)
  assert_true(generic_provider.files() is None)
  assert_true(generic_provider.skills() is None)
  try generic_provider.image_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.ImageModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected Alibaba image model rejection")
  }
}

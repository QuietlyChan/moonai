///|
test "ByteDance image encodes Seedream provider options" {
  let model = ByteDanceImageModel::new(
    "seedream-5-0-260128",
    api_key="test-key",
  )
  let warnings : Array[@provider.Warning] = []
  let body = model.create_body(
    @provider.ImageModelV4CallOptions::new(prompt="Combine", size="2048x2048", files=[
      @provider.ImageModelV4File::bytes(data=b"image", media_type="image/png"),
      @provider.ImageModelV4File::url("https://example.com/input.png"),
    ]),
    ByteDanceImageModelOptions::new(
      watermark=false,
      output_format="png",
      size="2K",
      sequential_image_generation="auto",
      max_images=4,
      optimize_prompt_mode="fast",
    ),
  )
  ignore(warnings)
  json_inspect(body, content={
    "model": "seedream-5-0-260128",
    "response_format": "b64_json",
    "prompt": "Combine",
    "image": ["data:image/png;base64,aW1hZ2U=", "https://example.com/input.png"],
    "size": "2K",
    "watermark": false,
    "output_format": "png",
    "sequential_image_generation": "auto",
    "sequential_image_generation_options": { "max_images": 4 },
    "optimize_prompt_options": { "mode": "fast" },
  })
}

///|
test "ByteDance video encodes frames references and standard controls" {
  let model = ByteDanceVideoModel::new(
    "seedance-1-5-pro-251215",
    api_key="test-key",
    base_url="https://ark.ap-southeast.bytepluses.com/api/v3",
    headers=Map([]),
    idle_timeout_ms=120_000,
    http_transport=@provider_utils.native_http_transport(),
  )
  let warnings : Array[@provider.Warning] = []
  let body = model.create_body(
    @provider.VideoModelV4CallOptions::new(
      prompt="Orbit",
      n=2,
      aspect_ratio="16:9",
      resolution="1920x1080",
      duration=5.0,
      fps=30,
      seed=42,
      generate_audio=true,
      frame_images=[
        @provider.VideoModelV4FrameImage::first(
          @provider.VideoModelV4File::url(
            "https://example.com/first.png",
            media_type="image/png",
          ),
        ),
        @provider.VideoModelV4FrameImage::last(
          @provider.VideoModelV4File::url(
            "https://example.com/last.png",
            media_type="image/png",
          ),
        ),
      ],
    ),
    ByteDanceVideoModelOptions::new(
      watermark=false,
      camera_fixed=true,
      service_tier="flex",
      reference_audio=["https://example.com/audio.mp3"],
    ),
    warnings,
  )
  json_inspect(body, content={
    "model": "seedance-1-5-pro-251215",
    "content": [
      { "type": "text", "text": "Orbit" },
      {
        "type": "image_url",
        "image_url": { "url": "https://example.com/first.png" },
        "role": "first_frame",
      },
      {
        "type": "image_url",
        "image_url": { "url": "https://example.com/last.png" },
        "role": "last_frame",
      },
      {
        "type": "audio_url",
        "audio_url": { "url": "https://example.com/audio.mp3" },
        "role": "reference_audio",
      },
    ],
    "ratio": "16:9",
    "duration": 5,
    "seed": 42,
    "resolution": "1080p",
    "generate_audio": true,
    "watermark": false,
    "camera_fixed": true,
    "service_tier": "flex",
  })
  assert_eq(warnings.length(), 2)
  assert_true(warnings[0] is @provider.Warning::Unsupported(feature="fps", ..))
  assert_true(warnings[1] is @provider.Warning::Unsupported(feature="n", ..))
}

///|
priv struct ByteDanceProtocolTransport {
  responses : Array[String]
  next : Ref[Int]
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn ByteDanceProtocolTransport::new(
  responses : Array[String],
) -> ByteDanceProtocolTransport {
  { responses, next: Ref(0), requests: [] }
}

///|
impl @provider_utils.HttpTransport for ByteDanceProtocolTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  guard self.next.val < self.responses.length() else {
    fail("unexpected ByteDance request")
  }
  let body = self.responses[self.next.val]
  self.next.val = self.next.val + 1
  @provider_utils.HttpResponse::text(status_code=200, body~)
}

///|
impl @provider_utils.HttpTransport for ByteDanceProtocolTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("ByteDance streaming transport was not expected")
}

///|
async test "ByteDance image returns base64 data through V4" {
  let transport = ByteDanceProtocolTransport::new([
    "{\"data\":[{\"b64_json\":\"test1234\"},{\"b64_json\":\"test5678\"}]}",
  ])
  let model = byte_dance_image(
    "seedream-5-0-260128",
    api_key="test-key",
    base_url="https://mock.bytedance.test",
    http_transport=transport,
  )
  let result = model.do_generate(
    @provider.ImageModelV4CallOptions::new(
      prompt="A MoonBit logo",
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_eq(result.images.length(), 2)
  assert_true(result.images[0].data is @provider.Base64("test1234"))
  assert_eq(
    transport.requests[0].url,
    "https://mock.bytedance.test/images/generations",
  )
}

///|
async test "ByteDance video polls and preserves task metadata" {
  let transport = ByteDanceProtocolTransport::new([
    "{\"id\":\"task-1\"}", "{\"id\":\"task-1\",\"status\":\"succeeded\",\"content\":{\"video_url\":\"https://cdn.test/video.mp4\"},\"usage\":{\"completion_tokens\":100}}",
  ])
  let model = byte_dance_video(
    "seedance-1-0-pro-250528",
    api_key="test-key",
    base_url="https://mock.bytedance.test",
    http_transport=transport,
  )
  let result = model.do_generate(
    @provider.VideoModelV4CallOptions::new(
      prompt="City",
      provider_options=ByteDanceVideoModelOptions::new(
        poll_interval_ms=1,
        poll_timeout_ms=1000,
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_true(
    result.videos[0]
    is @provider.VideoV4Url(
      url="https://cdn.test/video.mp4",
      media_type="video/mp4"
    ),
  )
  json_inspect(result.provider_metadata, content={
    "bytedance": { "taskId": "task-1", "usage": { "completion_tokens": 100 } },
  })
  assert_eq(transport.requests.length(), 2)
  assert_eq(transport.requests[0].meth, @provider_utils.HttpPost)
  assert_eq(transport.requests[1].meth, @provider_utils.HttpGet)
}

///|
test "ByteDance public provider exposes image and video V4 models" {
  let provider = createByteDance(api_key="test-key")
  let generic = provider as &@provider.ProviderV4
  assert_eq(generic.specification_version(), "v4")
  assert_eq(provider.imageModel("seedream-5-0").provider(), "bytedance.image")
  assert_eq(
    provider.videoModel("seedance-1-5-pro").provider(),
    "bytedance.video",
  )
}

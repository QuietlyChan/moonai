///|
test "xai reasoning effort whitelist matches upstream grok-4.20 rule" {
  assert_true(supports_reasoning_effort("grok-4.3"))
  assert_true(supports_reasoning_effort("grok-4.20-multi-agent"))
  assert_false(supports_reasoning_effort("grok-4.20-reasoning"))
  assert_false(supports_reasoning_effort("grok-4.20-non-reasoning"))
  assert_false(supports_reasoning_effort("grok-4.20-0309-reasoning"))
  assert_true(supports_reasoning_effort("grok-4.20"))
}

///|
test "xai finish reason maps function_call onto tool calls" {
  assert_eq(xai_map_finish_reason(Some("function_call")), {
    unified: @provider.V4FinishToolCalls,
    raw: Some("function_call"),
  })
  assert_eq(xai_map_finish_reason(Some("stop")), {
    unified: @provider.V4FinishStop,
    raw: Some("stop"),
  })
}

///|
test "xai image request body separates single and multi image inputs" {
  let single = xai_image_request_body(
    "grok-2-image-v1",
    prompt=Some("a cat"),
    n=1,
    aspect_ratio=Some("1:1"),
    image_urls=["data:image/png;base64,AA=="],
    provider_options=Map([("output_format", Json::string("jpeg"))]),
  )
  assert_true(
    single
    is {
      "model": "grok-2-image-v1",
      "prompt": "a cat",
      "aspect_ratio": "1:1",
      "image": { "url": "data:image/png;base64,AA==", "type": "image_url", .. },
      "output_format": "jpeg",
      ..
    },
  )
  let multi = xai_image_request_body(
    "grok-2-image-v1",
    prompt=Some("a cat"),
    n=1,
    aspect_ratio=None,
    image_urls=["a", "b"],
    provider_options=Map([]),
  )
  assert_true(
    multi is { "images": [{ "url": "a", .. }, { "url": "b", .. }], .. },
  )
}

///|
test "xai image response decode flags moderation blocks" {
  let (images, blocked) = decode_xai_image_response({
    "data": [{ "b64_json": "AA==" }],
  })
  assert_eq(images.length(), 1)
  assert_false(blocked)
  let (url_images, _) = decode_xai_image_response({
    "data": [{ "url": "https://img.example/x.png" }],
  })
  assert_eq(
    url_images[0].data,
    @provider.ImageData::Url("https://img.example/x.png"),
  )
  let (_, blocked2) = decode_xai_image_response({
    "data": [{ "b64_json": "AA==", "respect_moderation": false }],
  })
  assert_true(blocked2)
}

///|
test "xai agent tool factories and wire encoding" {
  let web_search = xai_web_search_tool(
    allowed_domains=["example.com"],
    enable_image_understanding=true,
  )
  assert_true(
    web_search is @provider.V4ProviderTool({ id: "xai.web_search", .. }),
  )
  guard web_search is @provider.V4ProviderTool(value) else {
    fail("expected provider tool")
  }
  let encoded = xai_encode_provider_tool(value)
  assert_true(
    encoded
    is Some(
      {
        "type": "web_search",
        "allowed_domains": ["example.com"],
        "enable_image_understanding": true,
        ..
      }
    ),
  )
  let code = xai_code_execution_tool()
  guard code is @provider.V4ProviderTool(code_value) else {
    fail("expected provider tool")
  }
  assert_true(
    xai_encode_provider_tool(code_value)
    is Some({ "type": "code_interpreter", .. }),
  )
}

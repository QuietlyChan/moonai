///|
test "encode OpenAI-compatible image request" {
  json_inspect(
    encode_image_request(
      "image-model",
      @provider.ImageCallOptions::new("A MoonBit logo", n=2, size="1024x1024", provider_options={
        "openaiCompatible": { "quality": "hd" },
      }),
      include_response_format=true,
    ),
    content={
      "model": "image-model",
      "prompt": "A MoonBit logo",
      "n": 2,
      "size": "1024x1024",
      "response_format": "b64_json",
      "quality": "hd",
    },
  )
}

///|
test "image provider options use OpenAI wire names" {
  let options = @provider.ImageCallOptions::new("A MoonBit logo", provider_options={
    "openai": {
      "outputFormat": "webp",
      "outputCompression": 80,
      "inputFidelity": "high",
    },
  })
  json_inspect(
    encode_image_request("gpt-image-1", options, provider_name="openai.image"),
    content={
      "model": "gpt-image-1",
      "prompt": "A MoonBit logo",
      "n": 1,
      "output_format": "webp",
      "output_compression": 80,
      "input_fidelity": "high",
    },
  )
}

///|
test "decode base64 and URL image response" {
  let response = decode_image_response({
    "data": [
      { "b64_json": "aGVsbG8=", "revised_prompt": "A revised logo" },
      { "url": "https://example.com/image.png" },
    ],
    "usage": { "input_tokens": 5, "output_tokens": 7, "total_tokens": 12 },
  })
  assert_eq(response.images, [
    @provider.GeneratedImage::new(
      @provider.ImageData::Base64("aGVsbG8="),
      revised_prompt="A revised logo",
    ),
    @provider.GeneratedImage::new(
      @provider.ImageData::Url("https://example.com/image.png"),
    ),
  ])
  assert_eq(response.usage.total_tokens, 12)
}

///|
test "image decoder rejects provider errors and missing payloads" {
  try
    decode_image_response({ "error": { "message": "safety rejection" } })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("safety rejection"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected image provider error")
  }
  try decode_image_response({ "data": [Json::empty_object()] }) catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("b64_json or url"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing image payload error")
  }
}

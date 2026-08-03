///|
test "encode OpenAI-compatible image request" {
  json_inspect(
    encode_image_request(
      "image-model",
      @moonai.ImageCallOptions::new(
        "A MoonBit logo",
        n=2,
        size="1024x1024",
        provider_options=Map([("quality", ("hd" : Json))]),
      ),
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
test "decode base64 and URL image response" {
  let response = decode_image_response({
    "data": [
      { "b64_json": "aGVsbG8=", "revised_prompt": "A revised logo" },
      { "url": "https://example.com/image.png" },
    ],
    "usage": { "input_tokens": 5, "output_tokens": 7, "total_tokens": 12 },
  })
  assert_eq(response.images, [
    @moonai.GeneratedImage::new(
      @moonai.ImageData::Base64("aGVsbG8="),
      revised_prompt="A revised logo",
    ),
    @moonai.GeneratedImage::new(
      @moonai.ImageData::Url("https://example.com/image.png"),
    ),
  ])
  assert_eq(response.usage.total_tokens, 12)
}

///|
test "image decoder rejects provider errors and missing payloads" {
  try
    decode_image_response({ "error": { "message": "safety rejection" } })
  catch {
    Failure::Failure(message) =>
      assert_true(message.contains("safety rejection"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected image provider error")
  }
  try decode_image_response({ "data": [Json::empty_object()] }) catch {
    Failure::Failure(message) =>
      assert_true(message.contains("b64_json or url"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing image payload error")
  }
}

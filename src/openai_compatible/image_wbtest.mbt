///|
test "encode OpenAI-compatible V4 image request data" {
  json_inspect(
    encode_image_request_data(
      "image-model",
      Some("A MoonBit logo"),
      2,
      Some("1024x1024"),
      { "quality": "hd" },
      true,
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
  json_inspect(
    encode_image_request_data(
      "gpt-image-1",
      Some("A MoonBit logo"),
      1,
      None,
      {
        "outputFormat": "webp",
        "outputCompression": 80,
        "inputFidelity": "high",
      },
      false,
    ),
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
test "decode base64 image response data" {
  let (images, usage) = decode_image_response_data(
    {
      "data": [{ "b64_json": "aGVsbG8=", "revised_prompt": "A revised logo" }],
      "usage": { "input_tokens": 5, "output_tokens": 7, "total_tokens": 12 },
    },
    default_openai_compatible_error_structure(),
  )
  assert_eq(images, [
    @provider.GeneratedImage::new(
      @provider.ImageData::Base64("aGVsbG8="),
      revised_prompt="A revised logo",
    ),
  ])
  assert_eq(usage.unwrap().total_tokens, Some(12))
}

///|
test "image decoder rejects provider errors and missing payloads" {
  let error_structure = default_openai_compatible_error_structure()
  try
    decode_image_response_data(
      { "error": { "message": "safety rejection" } },
      error_structure,
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("safety rejection"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected image provider error")
  }
  try
    decode_image_response_data(
      { "data": [Json::empty_object()] },
      error_structure,
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("no b64_json"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing image payload error")
  }
}

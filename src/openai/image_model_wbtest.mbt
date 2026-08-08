///|
test "OpenAI image metadata preserves single-image token details" {
  let metadata = openai_image_metadata({
    "data": [{ "b64_json": "image" }],
    "usage": {
      "input_tokens": 12,
      "input_tokens_details": { "image_tokens": 7, "text_tokens": 5 },
    },
  })
  json_inspect(metadata["openai"], content={
    "images": [{ "imageTokens": 7, "textTokens": 5 }],
  })
}

///|
test "OpenAI image metadata distributes token detail remainder to last image" {
  let metadata = openai_image_metadata({
    "data": [
      { "b64_json": "image-1" },
      { "b64_json": "image-2" },
      { "b64_json": "image-3" },
    ],
    "usage": {
      "input_tokens_details": { "image_tokens": 194, "text_tokens": 28 },
    },
  })
  json_inspect(metadata["openai"], content={
    "images": [
      { "imageTokens": 64, "textTokens": 9 },
      { "imageTokens": 64, "textTokens": 9 },
      { "imageTokens": 66, "textTokens": 10 },
    ],
  })
}

///|
test "OpenAI image metadata omits absent token details" {
  let metadata = openai_image_metadata({
    "data": [{ "b64_json": "image" }],
    "usage": { "input_tokens": 1 },
  })
  json_inspect(metadata["openai"], content={ "images": [Json::empty_object()] })
}

///|
test "OpenAI image response rejects URL-only image items" {
  try
    decode_openai_image_response_data({
      "data": [{ "url": "https://example.com/image.png" }],
    })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("no b64_json"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected URL-only image item to be rejected")
  }
}

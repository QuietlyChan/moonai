///|
test "OpenAI-compatible V4 embedding keeps absent usage absent" {
  let (_, usage) = decode_embedding_response_data(
    { "data": [{ "embedding": [0.1, 0.2] }] },
    default_openai_compatible_error_structure(),
  )
  assert_eq(usage, None)
}

///|
test "OpenAI-compatible V4 image keeps absent usage absent" {
  let (images, usage) = decode_image_response_data(
    { "data": [{ "b64_json": "aW1hZ2U=" }] },
    default_openai_compatible_error_structure(),
  )
  assert_eq(images.length(), 1)
  assert_eq(usage, None)
}

///|
test "OpenAI-compatible V4 image request omits an absent prompt" {
  json_inspect(
    encode_image_request_data("image-model", None, 1, None, Map([]), false),
    content={ "model": "image-model", "n": 1 },
  )
}

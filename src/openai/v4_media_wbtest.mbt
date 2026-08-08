///|
test "OpenAI V4 embedding keeps absent usage absent" {
  let (_, usage) = decode_openai_embedding_response({
    "data": [{ "embedding": [0.1, 0.2] }],
  })
  assert_eq(usage, None)
}

///|
test "OpenAI V4 image keeps absent usage absent" {
  let (images, usage) = decode_openai_image_response_data({
    "data": [{ "b64_json": "aW1hZ2U=" }],
  })
  assert_eq(images.length(), 1)
  assert_eq(usage, None)
}

///|
test "OpenAI V4 image request omits an absent prompt" {
  json_inspect(
    openai_image_generation_body(
      "gpt-image-1",
      None,
      1,
      None,
      {
        quality: None,
        style: None,
        background: None,
        moderation: None,
        output_format: None,
        output_compression: None,
        input_fidelity: None,
        user: None,
      },
      false,
    ),
    content={ "model": "gpt-image-1", "n": 1 },
  )
}

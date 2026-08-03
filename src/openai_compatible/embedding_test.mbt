///|
test "encode OpenAI-compatible embedding request" {
  json_inspect(
    encode_embedding_request(
      "text-embedding-test",
      ["first", "second"],
      @moonai.EmbeddingOptions::new(
        dimensions=256,
        user="user-1",
        provider_options=Map([("vendor_option", (true : Json))]),
      ),
    ),
    content={
      "model": "text-embedding-test",
      "input": ["first", "second"],
      "encoding_format": "float",
      "dimensions": 256,
      "user": "user-1",
      "vendor_option": true,
    },
  )
}

///|
test "decode OpenAI-compatible embedding response" {
  let response = decode_embedding_response({
    "data": [
      { "object": "embedding", "index": 0, "embedding": [0.1, -0.2] },
      { "object": "embedding", "index": 1, "embedding": [0.3, 0.4] },
    ],
    "usage": { "prompt_tokens": 7, "total_tokens": 7 },
  })
  assert_eq(response.embeddings, [[0.1, -0.2], [0.3, 0.4]])
  assert_eq(response.usage, {
    input_tokens: 7,
    output_tokens: 0,
    total_tokens: 7,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
  })
}

///|
test "embedding decoder rejects provider errors and malformed vectors" {
  try
    decode_embedding_response({ "error": { "message": "quota exceeded" } })
  catch {
    Failure::Failure(message) => assert_true(message.contains("quota exceeded"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected embedding provider error")
  }
  try
    decode_embedding_response({ "data": [{ "embedding": [0.1, "bad"] }] })
  catch {
    Failure::Failure(message) => assert_true(message.contains("non-number"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected malformed embedding vector")
  }
}

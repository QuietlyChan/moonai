///|
test "encode OpenAI-compatible embedding request" {
  json_inspect(
    encode_embedding_request(
      "text-embedding-test",
      ["first", "second"],
      @provider.EmbeddingOptions::new(dimensions=256, user="user-1", provider_options={
        "openaiCompatible": { "vendor_option": true },
      }),
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
    cache_write_input_tokens: 0,
  })
}

///|
test "embedding decoder rejects provider errors and malformed vectors" {
  try
    decode_embedding_response({ "error": { "message": "quota exceeded" } })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("quota exceeded"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected embedding provider error")
  }
  try
    decode_embedding_response({ "data": [{ "embedding": [0.1, "bad"] }] })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("non-number"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected malformed embedding vector")
  }
}

///|
async test "OpenAI-compatible embedding enforces its configured batch limit" {
  let model = openai_compatible_embedding(
    provider_name="local-test",
    base_url="https://example.invalid/v1",
    model_id="embedding-model",
    max_embeddings_per_call=2,
  )
  try
    model.embed(["one", "two", "three"], @provider.EmbeddingOptions::new())
  catch {
    @provider.TooManyEmbeddingValuesForCallError(
      provider~,
      model_id~,
      max_embeddings_per_call~,
      values~
    ) => {
      assert_eq(provider, "local-test.embedding")
      assert_eq(model_id, "embedding-model")
      assert_eq(max_embeddings_per_call, 2)
      assert_eq(values, ["one", "two", "three"])
    }
    error => fail("unexpected embedding limit error: \{error}")
  } noraise {
    _ => fail("expected the configured embedding limit to be enforced")
  }
}

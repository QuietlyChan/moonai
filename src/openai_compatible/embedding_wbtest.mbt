///|
test "encode OpenAI-compatible V4 embedding request data" {
  json_inspect(
    encode_embedding_request_data("text-embedding-test", ["first", "second"], {
      "dimensions": 256,
      "user": "user-1",
      "vendor_option": true,
    }),
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
test "decode OpenAI-compatible V4 embedding response data" {
  let (embeddings, usage_tokens) = decode_embedding_response_data(
    {
      "data": [
        { "object": "embedding", "index": 0, "embedding": [0.1, -0.2] },
        { "object": "embedding", "index": 1, "embedding": [0.3, 0.4] },
      ],
      "usage": { "prompt_tokens": 7, "total_tokens": 7 },
    },
    default_openai_compatible_error_structure(),
  )
  assert_eq(embeddings, [[0.1, -0.2], [0.3, 0.4]])
  assert_eq(usage_tokens, Some(7))
}

///|
test "embedding decoder rejects provider errors and malformed vectors" {
  let error_structure = default_openai_compatible_error_structure()
  try
    decode_embedding_response_data(
      { "error": { "message": "quota exceeded" } },
      error_structure,
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("quota exceeded"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected embedding provider error")
  }
  try
    decode_embedding_response_data(
      { "data": [{ "embedding": [0.1, "bad"] }] },
      error_structure,
    )
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
  let concrete = openai_compatible_embedding(
    provider_name="local-test",
    base_url="https://example.invalid/v1",
    model_id="embedding-model",
    max_embeddings_per_call=2,
  )
  let model = concrete as &@provider.EmbeddingModelV4
  try
    model.do_embed(
      @provider.EmbeddingModelV4CallOptions::new(["one", "two", "three"]),
    )
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

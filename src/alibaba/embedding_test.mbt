///|
async test "Alibaba embedding rejects a direct call above its batch limit" {
  let values : Array[String] = []
  for index = 0; index < 11; index = index + 1 {
    values.push("value-{index}")
  }
  let model = alibaba_embedding("text-embedding-v4", api_key="unused")
  try model.embed(values, @provider.EmbeddingOptions::new()) catch {
    @provider.TooManyEmbeddingValuesForCallError(
      provider~,
      model_id~,
      max_embeddings_per_call~,
      values=provided_values
    ) => {
      assert_eq(provider, "alibaba.embedding")
      assert_eq(model_id, "text-embedding-v4")
      assert_eq(max_embeddings_per_call, 10)
      assert_eq(provided_values.length(), 11)
    }
    error => fail("unexpected embedding limit error: \{error}")
  } noraise {
    _ => fail("expected the direct embedding call to reject its batch")
  }
}

///|
async test "Alibaba embedding reports sparse-only output as unsupported" {
  let model = alibaba_embedding("text-embedding-v4", api_key="unused")
  let options = @provider.EmbeddingOptions::new(provider_options={
    "alibaba": { "outputType": "sparse" },
  })
  try model.embed(["MoonBit"], options) catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_true(functionality.contains("outputType 'sparse'"))
    error => fail("unexpected sparse embedding error: \{error}")
  } noraise {
    _ => fail("expected sparse-only embedding output to be rejected")
  }
}

///|
test "Alibaba typed embedding options validate enum values" {
  try AlibabaEmbeddingModelOptions::new(text_type="passage") catch {
    _ => ()
  } noraise {
    _ => fail("expected an invalid text_type to be rejected")
  }
  try AlibabaEmbeddingModelOptions::new(output_type="binary") catch {
    _ => ()
  } noraise {
    _ => fail("expected an invalid output_type to be rejected")
  }
}

///|
priv struct AlibabaEmbeddingSuccessTransport {
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn AlibabaEmbeddingSuccessTransport::new() -> AlibabaEmbeddingSuccessTransport {
  { requests: [] }
}

///|
impl @provider_utils.HttpTransport for AlibabaEmbeddingSuccessTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  @provider_utils.HttpResponse::text(
    status_code=200,
    headers={ "x-request-id": "embedding-1" },
    body="{\"output\":{\"embeddings\":[{\"embedding\":[3,4],\"text_index\":1,\"sparse_embedding\":[{\"index\":2,\"value\":0.5}]},{\"embedding\":[1,2],\"text_index\":0}]},\"usage\":{\"total_tokens\":7}}",
  )
}

///|
impl @provider_utils.HttpTransport for AlibabaEmbeddingSuccessTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "Alibaba embedding sorts values and exposes sparse metadata" {
  let transport = AlibabaEmbeddingSuccessTransport::new()
  let model = alibaba_embedding(
    "text-embedding-v4",
    api_key="test-key",
    base_url="https://mock.alibaba.test/api/v1",
    http_transport=transport,
  )
  let result = model.embed(
    ["first", "second"],
    @provider.EmbeddingOptions::new(
      provider_options=AlibabaEmbeddingModelOptions::new(
        text_type="document",
        dimension=2,
        output_type="dense&sparse",
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_eq(result.embeddings, [[1.0, 2.0], [3.0, 4.0]])
  assert_eq(result.usage.input_tokens, 7)
  assert_eq(result.usage.total_tokens, 7)
  assert_eq(transport.requests.length(), 1)
  json_inspect(@json.parse(transport.requests[0].body_text()), content={
    "model": "text-embedding-v4",
    "input": { "texts": ["first", "second"] },
    "parameters": {
      "text_type": "document",
      "dimension": 2,
      "output_type": "dense&sparse",
    },
  })
  json_inspect(result.provider_metadata["alibaba"], content={
    "sparseEmbeddings": [
      { "textIndex": 1, "sparseEmbedding": [{ "index": 2, "value": 0.5 }] },
    ],
  })
  assert_eq(result.response.unwrap().status_code, Some(200))
  assert_eq(
    result.response.unwrap().headers.get("x-request-id"),
    Some("embedding-1"),
  )
}

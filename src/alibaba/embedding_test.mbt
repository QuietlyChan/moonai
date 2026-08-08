///|
async test "Alibaba embedding rejects a direct call above its batch limit" {
  let values : Array[String] = []
  for index = 0; index < 11; index = index + 1 {
    values.push("value-\{index}")
  }
  let model = create_alibaba(api_key="unused").embedding("text-embedding-v4")
  try model.do_embed(@provider.EmbeddingModelV4CallOptions::new(values)) catch {
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
  let model = create_alibaba(api_key="unused").embedding("text-embedding-v4")
  let options = @provider.EmbeddingModelV4CallOptions::new(["MoonBit"], provider_options={
    "alibaba": { "outputType": "sparse" },
  })
  try model.do_embed(options) catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_true(functionality.contains("outputType 'sparse'"))
    error => fail("unexpected sparse embedding error: \{error}")
  } noraise {
    _ => fail("expected sparse-only embedding output to be rejected")
  }
}

///|
async test "Alibaba V4 embedding rejects a call above its batch limit" {
  let values : Array[String] = []
  for index = 0; index < 11; index = index + 1 {
    values.push("value-\{index}")
  }
  let model = create_alibaba(api_key="unused").embedding("text-embedding-v4")
  try model.do_embed(@provider.EmbeddingModelV4CallOptions::new(values)) catch {
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
    error => fail("unexpected V4 embedding limit error: \{error}")
  } noraise {
    _ => fail("expected the V4 embedding call to reject its batch")
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
test "Alibaba embedding dimension validation matches the AI SDK schema" {
  let options = AlibabaEmbeddingModelOptions::new(dimension=0)
  assert_eq(options.dimension, Some(0))
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
    body="{\"output\":{\"embeddings\":[{\"embedding\":[3,4],\"text_index\":1,\"sparse_embedding\":[{\"index\":2,\"value\":0.5,\"token\":\"moon\"}]},{\"embedding\":[1,2],\"text_index\":0}]},\"usage\":{\"total_tokens\":7}}",
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
priv struct AlibabaEmbeddingNoUsageTransport {}

///|
impl @provider_utils.HttpTransport for AlibabaEmbeddingNoUsageTransport with fn fetch(
  _self,
  _request,
) {
  @provider_utils.HttpResponse::text(
    status_code=200,
    headers={ "x-request-id": "embedding-no-usage" },
    body="{\"output\":{\"embeddings\":[{\"embedding\":[1,2],\"text_index\":0,\"sparse_embedding\":null}]}}",
  )
}

///|
impl @provider_utils.HttpTransport for AlibabaEmbeddingNoUsageTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "Alibaba V4 embedding omits absent usage and null sparse metadata" {
  let model = create_alibaba(
    api_key="test-key",
    embedding_base_url="https://mock.alibaba.test/api/v1",
    http_transport=AlibabaEmbeddingNoUsageTransport::{  },
  ).embedding("text-embedding-v4")
  let result = model.do_embed(
    @provider.EmbeddingModelV4CallOptions::new(
      ["MoonBit"],
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_eq(result.embeddings, [[1.0, 2.0]])
  assert_true(result.usage is None)
  assert_eq(result.provider_metadata.length(), 0)
  assert_eq(
    result.response.unwrap().headers.get("x-request-id"),
    Some("embedding-no-usage"),
  )
}

///|
async test "Alibaba embedding sorts values and exposes sparse metadata" {
  let transport = AlibabaEmbeddingSuccessTransport::new()
  let model = create_alibaba(
    api_key="test-key",
    embedding_base_url="https://mock.alibaba.test/api/v1",
    http_transport=transport,
  ).embedding("text-embedding-v4")
  let result = model.do_embed(
    @provider.EmbeddingModelV4CallOptions::new(
      ["first", "second"],
      provider_options=AlibabaEmbeddingModelOptions::new(
        text_type="document",
        dimension=2,
        output_type="dense&sparse",
      ).to_provider_options(),
      retry_policy=@provider.RetryPolicy::none(),
    ),
  )
  assert_eq(result.embeddings, [[1.0, 2.0], [3.0, 4.0]])
  assert_eq(result.usage.unwrap().tokens, Some(7))
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
      {
        "textIndex": 1,
        "sparseEmbedding": [{ "index": 2, "value": 0.5, "token": "moon" }],
      },
    ],
  })
  assert_eq(result.response.unwrap().status_code, Some(200))
  assert_eq(
    result.response.unwrap().headers.get("x-request-id"),
    Some("embedding-1"),
  )
}

///|
priv struct AlibabaEmbeddingResponseTransport {
  status_code : Int
  body : String
}

///|
fn AlibabaEmbeddingResponseTransport::new(
  body : String,
  status_code? : Int = 200,
) -> AlibabaEmbeddingResponseTransport {
  { status_code, body }
}

///|
impl @provider_utils.HttpTransport for AlibabaEmbeddingResponseTransport with fn fetch(
  self,
  _request,
) {
  @provider_utils.HttpResponse::text(
    status_code=self.status_code,
    body=self.body,
  )
}

///|
impl @provider_utils.HttpTransport for AlibabaEmbeddingResponseTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "Alibaba embedding rejects malformed native responses" {
  let cases : Array[(String, String)] = [
    (
      "{\"output\":{\"embeddings\":[{\"embedding\":[1,\"bad\"],\"text_index\":0}]}}",
      "non-number",
    ),
    ("{\"output\":{\"embeddings\":[{\"text_index\":0}]}}", "invalid embedding"),
    ("{}", "output.embeddings"),
    (
      "{\"output\":{\"embeddings\":[{\"embedding\":[1],\"text_index\":0,\"sparse_embedding\":[{\"index\":\"bad\",\"value\":0.5}]}]}}",
      "invalid entry",
    ),
    (
      "{\"output\":{\"embeddings\":[{\"embedding\":[1],\"text_index\":0,\"sparse_embedding\":{}}]}}",
      "array or null",
    ),
    (
      "{\"output\":{\"embeddings\":[{\"embedding\":[1],\"text_index\":0}]},\"usage\":{}}",
      "invalid usage",
    ),
  ]
  for case in cases {
    let transport = AlibabaEmbeddingResponseTransport::new(case.0)
    let model = create_alibaba(
      api_key="test-key",
      embedding_base_url="https://mock.alibaba.test/api/v1",
      http_transport=transport,
    ).embedding("text-embedding-v4")
    try
      model.do_embed(
        @provider.EmbeddingModelV4CallOptions::new(
          ["MoonBit"],
          retry_policy=@provider.RetryPolicy::none(),
        ),
      )
    catch {
      @provider.APICallError(
        message~,
        status_code~,
        is_retryable~,
        data~,
        cause~,
        ..
      ) => {
        assert_eq(message, "Failed to process successful response")
        assert_eq(status_code, Some(200))
        assert_false(is_retryable)
        assert_eq(data, Some(@json.parse(case.0)))
        assert_true(cause.unwrap_or("").contains(case.1))
      }
      error => fail("unexpected embedding response error: \{error}")
    } noraise {
      _ => fail("expected malformed Alibaba embedding response rejection")
    }
  }
}

///|
async test "Alibaba embedding surfaces native API error messages" {
  let transport = AlibabaEmbeddingResponseTransport::new(
    "{\"message\":\"invalid embedding input\"}",
    status_code=400,
  )
  let model = create_alibaba(
    api_key="test-key",
    embedding_base_url="https://mock.alibaba.test/api/v1",
    http_transport=transport,
  ).embedding("text-embedding-v4")
  try
    model.do_embed(
      @provider.EmbeddingModelV4CallOptions::new(
        ["MoonBit"],
        retry_policy=@provider.RetryPolicy::none(),
      ),
    )
  catch {
    @provider.APICallError(message~, status_code~, url~, ..) => {
      assert_eq(message, "invalid embedding input")
      assert_eq(status_code, Some(400))
      assert_eq(
        url, "https://mock.alibaba.test/api/v1/services/embeddings/text-embedding/text-embedding",
      )
    }
    error => fail("unexpected Alibaba embedding API error: \{error}")
  } noraise {
    _ => fail("expected Alibaba embedding API error")
  }
}

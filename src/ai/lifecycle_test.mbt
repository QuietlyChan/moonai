///|
fn lifecycle_test_embedding_response() -> @provider.EmbeddingBatchResponse {
  @provider.EmbeddingBatchResponse::new(
    [[0.1, 0.2], [0.3, 0.4]],
    @provider.Usage::new(input_tokens=3, output_tokens=0),
  )
}

///|
async test "embed attributes runtime context through lifecycle events (#20583)" {
  let model = @testing.MockEmbeddingModel::new(
    lifecycle_test_embedding_response(),
    provider_name="test.embed",
  )
  let started : Array[(String, String, String, Json)] = []
  let ended : Array[(String, Int, Int)] = []
  let response = embed(
    model as &@provider.EmbeddingModelV4,
    "hello world",
    runtime_context={ "requestId": "req-embed-1" },
    on_start=event => {
      assert_eq(event.values.length(), 1)
      assert_eq(event.values[0], "hello world")
      started.push(
        (
          event.call_id,
          event.operation_id,
          event.provider,
          event.runtime_context,
        ),
      )
    },
    on_end=event => {
      ended.push(
        (
          event.operation_id,
          event.usage.input_tokens,
          event.embeddings[0].length(),
        ),
      )
    },
  )
  assert_eq(response.embedding, [0.1, 0.2])
  assert_eq(started.length(), 1)
  let (call_id, operation_id, provider, context) = started[0]
  assert_true(call_id != "")
  assert_eq(operation_id, "ai.embed")
  assert_eq(provider, "test.embed")
  assert_eq(context, { "requestId": "req-embed-1" })
  assert_eq(ended, [("ai.embed", 3, 2)])
}

///|
async test "embedMany keeps the same runtime context contract (#20583)" {
  let model = @testing.MockEmbeddingModel::new(
    lifecycle_test_embedding_response(),
    provider_name="test.embed",
  )
  let started : Array[(String, Int, Json)] = []
  let response = embed_many(
    model as &@provider.EmbeddingModelV4,
    ["one", "two"],
    runtime_context={ "requestId": "req-embed-many" },
    on_start=event => {
      started.push(
        (event.operation_id, event.values.length(), event.runtime_context),
      )
    },
  )
  assert_eq(response.embeddings.length(), 2)
  assert_eq(started, [("ai.embedMany", 2, { "requestId": "req-embed-many" })])
}

///|
async test "embed lifecycle callback failures never break the operation" {
  let model = @testing.MockEmbeddingModel::new(
    lifecycle_test_embedding_response(),
    provider_name="test.embed",
  )
  let response = embed(
    model as &@provider.EmbeddingModelV4,
    "resilient",
    on_start=_ => fail("callback start failure"),
    on_end=_ => fail("callback end failure"),
  )
  assert_eq(response.embedding, [0.1, 0.2])
}

///|
async test "rerank attributes runtime context through lifecycle events (#20583)" {
  let model = @testing.MockRerankingModelV4::new(
    @provider.RerankingModelV4Result::new(
      [
        @provider.RerankingModelV4Ranking::new(1, 0.9),
        @provider.RerankingModelV4Ranking::new(0, 0.1),
      ],
      response?=None,
      provider_metadata=Map([]),
      warnings=[],
    ),
    provider_name="test.rerank",
  )
  let started : Array[(String, Json, Int, String)] = []
  let ended : Array[(String, Int)] = []
  let result = rerank(
    model as &@provider.RerankingModelV4,
    @provider.RerankingModelV4Documents::TextDocuments(["a", "b"]),
    "query",
    runtime_context={ "requestId": "req-rerank" },
    on_start=event => {
      started.push(
        (
          event.operation_id,
          event.runtime_context,
          event.documents.length(),
          event.query,
        ),
      )
    },
    on_end=event => {
      ended.push((event.operation_id, event.ranking[0].original_index))
    },
  )
  assert_eq(result.ranking[0].original_index, 1)
  assert_eq(started, [("ai.rerank", { "requestId": "req-rerank" }, 2, "query")])
  assert_eq(ended, [("ai.rerank", 1)])
}

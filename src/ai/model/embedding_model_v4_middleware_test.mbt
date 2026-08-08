///|
async fn transform_embedding_values(
  options : @provider.EmbeddingModelV4CallOptions,
  _model : &@provider.EmbeddingModelV4,
) -> @provider.EmbeddingModelV4CallOptions {
  @async.pause()
  @provider.EmbeddingModelV4CallOptions::new(
    ["transformed"],
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
async fn passthrough_embedding_result(
  context : @provider.EmbeddingModelV4MiddlewareContext,
) -> @provider.EmbeddingModelV4Result {
  context.embed()
}

///|
async test "embedding V4 middleware transforms and delegates calls" {
  let base = @testing.MockEmbeddingModel::new(
    @provider.EmbeddingBatchResponse::new(
      [[1.0, 2.0]],
      @provider.Usage::new(input_tokens=1, output_tokens=0),
    ),
    provider_name="base",
    model_id="base-embedding",
    max_embeddings_per_call=8,
    supports_parallel_calls=false,
  )
  let wrapped = wrapEmbeddingModel(
    base,
    @provider.EmbeddingModelV4Middleware::new(
      transform_params=transform_embedding_values,
      override_provider=_ => "wrapped",
      override_model_id=_ => "wrapped-embedding",
      override_max_embeddings_per_call=_ => Some(2),
      override_supports_parallel_calls=_ => true,
      wrap_embed=passthrough_embedding_result,
    ),
  )
  assert_eq(wrapped.specification_version(), "v4")
  assert_eq(wrapped.provider(), "wrapped")
  assert_eq(wrapped.model_id(), "wrapped-embedding")
  assert_eq(wrapped.max_embeddings_per_call(), Some(2))
  assert_true(wrapped.supports_parallel_calls())
  let result = wrapped.do_embed(
    @provider.EmbeddingModelV4CallOptions::new(["original"]),
  )
  assert_eq(base.captured_values(), ["transformed"])
  assert_eq(result.embeddings, [[1.0, 2.0]])
}

///|
test "embedding V4 middleware chain keeps the first wrapper outermost" {
  let base = @testing.MockEmbeddingModel::new(
    @provider.EmbeddingBatchResponse::new([[1.0]], @provider.Usage::zero()),
  )
  let wrapped = wrapEmbeddingModelChain(base, [
    @provider.EmbeddingModelV4Middleware::new(override_provider=_ => "outer"),
    @provider.EmbeddingModelV4Middleware::new(override_model_id=_ => {
      "inner-model"
    }),
  ])
  assert_eq(wrapped.provider(), "outer")
  assert_eq(wrapped.model_id(), "inner-model")
}

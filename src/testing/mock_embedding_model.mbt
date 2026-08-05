///|
/// Deterministic embedding model for SDK consumer tests.
pub struct MockEmbeddingModel {
  priv provider_name : String
  priv model_id : String
  priv max_embeddings : Int
  priv supports_parallel : Bool
  priv result : @provider.EmbeddingBatchResponse
  priv captured_values : Array[String]
  priv captured_batches : Array[Array[String]]
}

///|
/// Construct a deterministic embedding model.
pub fn MockEmbeddingModel::new(
  result : @provider.EmbeddingBatchResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-embedding-model",
  max_embeddings_per_call? : Int = 2048,
  supports_parallel_calls? : Bool = false,
) -> MockEmbeddingModel {
  {
    provider_name,
    model_id,
    max_embeddings: max_embeddings_per_call,
    supports_parallel: supports_parallel_calls,
    result,
    captured_values: [],
    captured_batches: [],
  }
}

///|
/// Return the values received during the latest call.
pub fn MockEmbeddingModel::captured_values(
  self : MockEmbeddingModel,
) -> Array[String] {
  self.captured_values.copy()
}

///|
/// Return all value batches received in call order.
pub fn MockEmbeddingModel::captured_batches(
  self : MockEmbeddingModel,
) -> Array[Array[String]] {
  [
    for batch in self.captured_batches => batch.copy()
  ]
}

///|
pub impl @provider.EmbeddingWireModel for MockEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingWireModel for MockEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingWireModel for MockEmbeddingModel with fn max_embeddings_per_call(
  self,
) -> Int {
  self.max_embeddings
}

///|
pub impl @provider.EmbeddingWireModel for MockEmbeddingModel with fn supports_parallel_calls(
  self,
) -> Bool {
  self.supports_parallel
}

///|
pub impl @provider.EmbeddingWireModel for MockEmbeddingModel with fn embed(
  self,
  values,
  options,
) {
  self.embed_values_for_v4(values, options)
}

///|
fn MockEmbeddingModel::embed_values_for_v4(
  self : MockEmbeddingModel,
  values : Array[String],
  _options : @provider.EmbeddingOptions,
) -> @provider.EmbeddingBatchResponse {
  self.captured_values.clear()
  for value in values {
    self.captured_values.push(value)
  }
  self.captured_batches.push(values.copy())
  guard self.result.embeddings.length() > 0 else { self.result }
  let embeddings : Array[Array[Double]] = []
  for index in 0..<values.length() {
    embeddings.push(
      self.result.embeddings[index % self.result.embeddings.length()],
    )
  }
  @provider.EmbeddingBatchResponse::new(embeddings, self.result.usage).with_diagnostics(
    self.result.request,
    self.result.response,
    self.result.provider_metadata,
    self.result.warnings,
  )
}

///|
/// V4 mock boundary used by high-level embedding tests.
pub impl @provider.EmbeddingModelV4 for MockEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for MockEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for MockEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for MockEmbeddingModel with fn max_embeddings_per_call(
  self,
) -> Int? {
  Some(self.max_embeddings)
}

///|
pub impl @provider.EmbeddingModelV4 for MockEmbeddingModel with fn supports_parallel_calls(
  self,
) -> Bool {
  self.supports_parallel
}

///|
pub impl @provider.EmbeddingModelV4 for MockEmbeddingModel with fn do_embed(
  self,
  options,
) {
  let legacy_options = @provider.EmbeddingOptions::new(
    dimensions?=None,
    user?=None,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
  @provider.EmbeddingModelV4Result::from_batch_response(
    self.embed_values_for_v4(options.values, legacy_options),
  )
}

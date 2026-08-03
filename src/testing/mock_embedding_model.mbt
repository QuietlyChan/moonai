///|
/// Deterministic embedding model for SDK consumer tests.
pub struct MockEmbeddingModel {
  priv provider_name : String
  priv model_id : String
  priv max_embeddings : Int
  priv result : @moonai.EmbeddingBatchResponse
  priv captured_values : Array[String]
  priv captured_batches : Array[Array[String]]
}

///|
/// Construct a deterministic embedding model.
pub fn MockEmbeddingModel::new(
  result : @moonai.EmbeddingBatchResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-embedding-model",
  max_embeddings_per_call? : Int = 2048,
) -> MockEmbeddingModel {
  {
    provider_name,
    model_id,
    max_embeddings: max_embeddings_per_call,
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
pub impl @moonai.EmbeddingModel for MockEmbeddingModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.EmbeddingModel for MockEmbeddingModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.EmbeddingModel for MockEmbeddingModel with fn max_embeddings_per_call(
  self,
) -> Int {
  self.max_embeddings
}

///|
pub impl @moonai.EmbeddingModel for MockEmbeddingModel with fn embed(
  self,
  values,
  _options,
) {
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
  @moonai.EmbeddingBatchResponse::new(embeddings, self.result.usage).with_diagnostics(
    self.result.request,
    self.result.response,
    self.result.provider_metadata,
    self.result.warnings,
  )
}

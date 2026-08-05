///|
/// Deterministic reranking model for high-level workflow tests.
pub struct MockRerankingModel {
  priv provider_name : String
  priv model_id : String
  priv result : @provider.RerankingResponse
  priv mut captured_options : @provider.RerankingCallOptions?
}

///|
/// Construct a deterministic reranking model.
pub fn MockRerankingModel::new(
  result : @provider.RerankingResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-reranker",
) -> MockRerankingModel {
  { provider_name, model_id, result, captured_options: None }
}

///|
/// Return the latest normalized call options, if the model was invoked.
pub fn MockRerankingModel::captured_options(
  self : MockRerankingModel,
) -> @provider.RerankingCallOptions? {
  self.captured_options
}

///|
pub impl @provider.RerankingModel for MockRerankingModel with fn provider(
  self : MockRerankingModel,
) -> String {
  self.provider_name
}

///|
pub impl @provider.RerankingModel for MockRerankingModel with fn model_id(
  self : MockRerankingModel,
) -> String {
  self.model_id
}

///|
pub impl @provider.RerankingModel for MockRerankingModel with fn rerank(
  self : MockRerankingModel,
  options : @provider.RerankingCallOptions,
) -> @provider.RerankingResponse {
  self.captured_options = Some(options)
  self.result
}

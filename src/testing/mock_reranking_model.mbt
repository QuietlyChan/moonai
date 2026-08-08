///|
/// Deterministic reranking model for high-level workflow tests.
pub struct MockRerankingModelV4 {
  priv provider_name : String
  priv model_id : String
  priv result : @provider.RerankingModelV4Result
  priv mut captured_options : @provider.RerankingModelV4CallOptions?
}

///|
/// Construct a deterministic reranking model.
pub fn MockRerankingModelV4::new(
  result : @provider.RerankingModelV4Result,
  provider_name? : String = "mock",
  model_id? : String = "mock-reranker",
) -> MockRerankingModelV4 {
  { provider_name, model_id, result, captured_options: None }
}

///|
/// Return the latest normalized call options, if the model was invoked.
pub fn MockRerankingModelV4::captured_options(
  self : MockRerankingModelV4,
) -> @provider.RerankingModelV4CallOptions? {
  self.captured_options
}

///|
pub impl @provider.RerankingModelV4 for MockRerankingModelV4 with fn specification_version(
  _self : MockRerankingModelV4,
) -> String {
  "v4"
}

///|
pub impl @provider.RerankingModelV4 for MockRerankingModelV4 with fn provider(
  self : MockRerankingModelV4,
) -> String {
  self.provider_name
}

///|
pub impl @provider.RerankingModelV4 for MockRerankingModelV4 with fn model_id(
  self : MockRerankingModelV4,
) -> String {
  self.model_id
}

///|
pub impl @provider.RerankingModelV4 for MockRerankingModelV4 with fn do_rerank(
  self : MockRerankingModelV4,
  options : @provider.RerankingModelV4CallOptions,
) -> @provider.RerankingModelV4Result {
  self.captured_options = Some(options)
  self.result
}

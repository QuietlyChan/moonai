///|
/// Event passed to the `on_start` callback of embed and embedMany
/// operations, emitted before the embedding model is called
/// (AI SDK #20583).
pub(all) struct EmbedStartEvent {
  /// User-defined runtime context for span attribution.
  runtime_context : Json
  /// Unique identifier for this embed call, used to correlate events.
  call_id : String
  /// Identifies the operation type (`ai.embed` or `ai.embedMany`).
  operation_id : String
  /// The provider identifier.
  provider : String
  /// The specific model identifier.
  model_id : String
  /// The value(s) being embedded.
  values : Array[String]
  /// Maximum retry count configured for the request.
  max_retries : Int
  /// Additional HTTP headers sent with the request.
  headers : Map[String, String]
  /// Additional provider-specific options.
  provider_options : Map[String, Json]
} derive(Debug)

///|
/// Event passed to the `on_end` callback of embed and embedMany operations,
/// emitted after the embedding model returns (AI SDK #20583).
pub(all) struct EmbedEndEvent {
  runtime_context : Json
  call_id : String
  operation_id : String
  provider : String
  model_id : String
  /// The value(s) that were embedded.
  values : Array[String]
  /// The resulting embedding(s), in input order.
  embeddings : Array[Array[Double]]
  /// Token usage aggregated across the operation.
  usage : Usage
  /// Warnings reported by the embedding model.
  warnings : Array[Warning]
  /// Provider-specific metadata from the response.
  provider_metadata : Map[String, Json]
} derive(Debug)

///|
/// Event passed to the `on_start` callback of rerank operations, emitted
/// before the reranking model is called (AI SDK #20583).
pub(all) struct RerankStartEvent {
  runtime_context : Json
  call_id : String
  operation_id : String
  provider : String
  model_id : String
  /// The documents being reranked (text entries as strings).
  documents : Array[Json]
  query : String
  top_n : Int?
  max_retries : Int
  headers : Map[String, String]
  provider_options : Map[String, Json]
} derive(Debug)

///|
/// Event passed to the `on_end` callback of rerank operations, emitted
/// after the reranking model returns (AI SDK #20583).
pub(all) struct RerankEndEvent {
  runtime_context : Json
  call_id : String
  operation_id : String
  provider : String
  model_id : String
  documents : Array[Json]
  query : String
  /// The selected ranking in provider order.
  ranking : Array[RerankItem]
  warnings : Array[Warning]
  provider_metadata : Map[String, Json]
} derive(Debug)

///|
/// Convert documents to the homogeneous JSON representation used by
/// rerank lifecycle events.
fn rerank_event_documents(
  documents : @provider.RerankingModelV4Documents,
) -> Array[Json] {
  match documents {
    @provider.RerankingModelV4Documents::TextDocuments(values) =>
      [
        for value in values => Json::string(value)
      ]
    @provider.RerankingModelV4Documents::ObjectDocuments(values) => values
  }
}

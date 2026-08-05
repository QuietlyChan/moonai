///|
/// Documents accepted by a reranking model. A call must use one document
/// representation consistently, matching AI SDK's v4 contract.
pub(all) enum RerankingDocuments {
  TextDocuments(Array[String])
  ObjectDocuments(Array[Json])
} derive(Debug, Eq)

///|
/// Construct text documents for reranking.
pub fn RerankingDocuments::text(values : Array[String]) -> RerankingDocuments {
  TextDocuments(values.copy())
}

///|
/// Construct JSON object documents for reranking.
pub fn RerankingDocuments::objects(values : Array[Json]) -> RerankingDocuments {
  ObjectDocuments(values.copy())
}

///|
/// Return the number of documents in a reranking request.
pub fn RerankingDocuments::length(self : RerankingDocuments) -> Int {
  match self {
    TextDocuments(values) => values.length()
    ObjectDocuments(values) => values.length()
  }
}

///|
/// A single provider-produced reranking entry.
pub(all) struct RerankingEntry {
  index : Int
  relevance_score : Double
} derive(Debug, Eq)

///|
/// Construct a reranking entry.
pub fn RerankingEntry::new(
  index : Int,
  relevance_score : Double,
) -> RerankingEntry {
  { index, relevance_score }
}

///|
/// Normalized options passed to a reranking model.
pub(all) struct RerankingCallOptions {
  documents : RerankingDocuments
  query : String
  top_n : Int?
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct reranking call options.
pub fn RerankingCallOptions::new(
  documents : RerankingDocuments,
  query : String,
  top_n? : Int,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> RerankingCallOptions {
  {
    documents,
    query,
    top_n,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Response returned by a reranking provider.
pub(all) struct RerankingResponse {
  ranking : Array[RerankingEntry]
  usage : Usage
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a reranking response.
pub fn RerankingResponse::new(
  ranking : Array[RerankingEntry],
  usage? : Usage = Usage::zero(),
  request? : RequestMetadata,
  response? : ResponseMetadata,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> RerankingResponse {
  { ranking, usage, request, response, provider_metadata, warnings }
}

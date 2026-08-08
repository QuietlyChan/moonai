///|
/// Documents accepted by a V4 reranking model. A call must use one document
/// representation consistently.
pub(all) enum RerankingModelV4Documents {
  TextDocuments(Array[String])
  ObjectDocuments(Array[Json])
} derive(Debug, Eq)

///|
/// Construct text documents for reranking.
pub fn RerankingModelV4Documents::text(
  values : Array[String],
) -> RerankingModelV4Documents {
  TextDocuments(values.copy())
}

///|
/// Construct JSON object documents for reranking.
pub fn RerankingModelV4Documents::objects(
  values : Array[Json],
) -> RerankingModelV4Documents {
  ObjectDocuments(values.copy())
}

///|
/// Return the number of documents in a reranking request.
pub fn RerankingModelV4Documents::length(
  self : RerankingModelV4Documents,
) -> Int {
  match self {
    TextDocuments(values) => values.length()
    ObjectDocuments(values) => values.length()
  }
}

///|
/// A single provider-produced reranking entry.
pub(all) struct RerankingModelV4Ranking {
  index : Int
  relevance_score : Double
} derive(Debug, Eq)

///|
/// Construct a reranking entry.
pub fn RerankingModelV4Ranking::new(
  index : Int,
  relevance_score : Double,
) -> RerankingModelV4Ranking {
  { index, relevance_score }
}

///|
/// Normalized options passed to a reranking model.
pub(all) struct RerankingModelV4CallOptions {
  documents : RerankingModelV4Documents
  query : String
  top_n : Int?
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct reranking call options.
pub fn RerankingModelV4CallOptions::new(
  documents : RerankingModelV4Documents,
  query : String,
  top_n? : Int,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> RerankingModelV4CallOptions {
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
pub(all) struct RerankingModelV4Result {
  ranking : Array[RerankingModelV4Ranking]
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a reranking response.
pub fn RerankingModelV4Result::new(
  ranking : Array[RerankingModelV4Ranking],
  response? : ResponseMetadata,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> RerankingModelV4Result {
  {
    ranking: ranking.copy(),
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

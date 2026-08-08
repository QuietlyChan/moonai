///|
/// A document retained alongside its provider-produced relevance score.
pub(all) enum RerankingDocument {
  TextDocument(String)
  ObjectDocument(Json)
} derive(Debug, Eq)

///|
/// One normalized reranking result entry.
pub(all) struct RerankItem {
  original_index : Int
  score : Double
  document : RerankingDocument
} derive(Debug, Eq)

///|
/// Result of a high-level reranking operation.
pub(all) struct RerankResult {
  original_documents : RerankingModelV4Documents
  reranked_documents : RerankingModelV4Documents
  ranking : Array[RerankItem]
  response : ResponseMetadata
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// Return a document at an original index.
fn reranking_document_at(
  documents : RerankingModelV4Documents,
  index : Int,
) -> RerankingDocument? {
  if index < 0 {
    return None
  }
  match documents {
    @provider.RerankingModelV4Documents::TextDocuments(values) =>
      if index >= values.length() {
        None
      } else {
        Some(RerankingDocument::TextDocument(values[index]))
      }
    @provider.RerankingModelV4Documents::ObjectDocuments(values) =>
      if index >= values.length() {
        None
      } else {
        Some(RerankingDocument::ObjectDocument(values[index]))
      }
  }
}

///|
/// Convert a selected ranking to the homogeneous document representation.
fn reranking_documents_from_items(
  items : Array[RerankItem],
  template : RerankingModelV4Documents,
) -> RerankingModelV4Documents {
  if items.length() == 0 {
    match template {
      @provider.RerankingModelV4Documents::TextDocuments(_) =>
        @provider.RerankingModelV4Documents::TextDocuments([])
      @provider.RerankingModelV4Documents::ObjectDocuments(_) =>
        @provider.RerankingModelV4Documents::ObjectDocuments([])
    }
  } else {
    match items[0].document {
      RerankingDocument::TextDocument(_) => {
        let values : Array[String] = []
        for item in items {
          match item.document {
            RerankingDocument::TextDocument(value) => values.push(value)
            RerankingDocument::ObjectDocument(_) => ()
          }
        }
        @provider.RerankingModelV4Documents::TextDocuments(values)
      }
      RerankingDocument::ObjectDocument(_) => {
        let values : Array[Json] = []
        for item in items {
          match item.document {
            RerankingDocument::ObjectDocument(value) => values.push(value)
            RerankingDocument::TextDocument(_) => ()
          }
        }
        @provider.RerankingModelV4Documents::ObjectDocuments(values)
      }
    }
  }
}

///|
/// Rerank text or JSON documents using a provider-neutral model.
///
/// The provider returns indices into `documents`; this function validates the
/// indices, preserves provider ordering, and reconstructs the selected
/// documents without exposing provider wire formats to callers.
pub async fn rerank(
  model : &RerankingModelV4,
  documents : RerankingModelV4Documents,
  query : String,
  top_n? : Int,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> RerankResult {
  check_cancellation(cancellation_token)
  if top_n is Some(value) && value < 0 {
    raise @provider.InvalidArgumentError(
      argument="topN",
      message="topN must be greater than or equal to zero",
    )
  }
  let original_documents = match documents {
    @provider.RerankingModelV4Documents::TextDocuments(values) =>
      @provider.RerankingModelV4Documents::TextDocuments(values.copy())
    @provider.RerankingModelV4Documents::ObjectDocuments(values) =>
      @provider.RerankingModelV4Documents::ObjectDocuments(values.copy())
  }
  if original_documents.length() == 0 {
    return {
      original_documents,
      reranked_documents: reranking_documents_from_items([], original_documents),
      ranking: [],
      response: ResponseMetadata::new(model_id=model.model_id()),
      provider_metadata: Map([]),
    }
  }
  let response = model.do_rerank(
    RerankingModelV4CallOptions::new(
      original_documents,
      query,
      top_n?,
      headers~,
      provider_options~,
      retry_policy~,
      cancellation_token?,
    ),
  )
  let items : Array[RerankItem] = []
  let seen : Map[Int, Bool] = Map([])
  for entry in response.ranking {
    guard reranking_document_at(original_documents, entry.index)
      is Some(document) else {
      raise @provider.InvalidResponseDataError(
        message="reranking response contains an out-of-range document index",
        data={ "index": entry.index },
      )
    }
    guard seen.get(entry.index) is None else {
      raise @provider.InvalidResponseDataError(
        message="reranking response contains a duplicate document index",
        data={ "index": entry.index },
      )
    }
    seen[entry.index] = true
    items.push({
      original_index: entry.index,
      score: entry.relevance_score,
      document,
    })
  }
  let reranked_documents = reranking_documents_from_items(
    items, original_documents,
  )
  {
    original_documents,
    reranked_documents,
    ranking: items,
    response: response.response.unwrap_or(
      ResponseMetadata::new(model_id=model.model_id()),
    ),
    provider_metadata: response.provider_metadata,
  }
}

///|
/// Rerank text documents without constructing the representation enum.
pub async fn rerank_text(
  model : &RerankingModelV4,
  documents : Array[String],
  query : String,
  top_n? : Int,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> RerankResult {
  rerank(
    model,
    RerankingModelV4Documents::text(documents),
    query,
    top_n?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// AI SDK-style camel-case spelling for `rerank`.
pub async fn rerankText(
  model : &RerankingModelV4,
  documents : Array[String],
  query : String,
  top_n? : Int,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> RerankResult {
  rerank_text(
    model,
    documents,
    query,
    top_n?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

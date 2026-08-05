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
  original_documents : RerankingDocuments
  reranked_documents : RerankingDocuments
  ranking : Array[RerankItem]
  usage : Usage
  response : ResponseMetadata
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Return a document at an original index.
fn reranking_document_at(
  documents : RerankingDocuments,
  index : Int,
) -> RerankingDocument? {
  if index < 0 {
    return None
  }
  match documents {
    @provider.RerankingDocuments::TextDocuments(values) =>
      if index >= values.length() {
        None
      } else {
        Some(RerankingDocument::TextDocument(values[index]))
      }
    @provider.RerankingDocuments::ObjectDocuments(values) =>
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
  template : RerankingDocuments,
) -> RerankingDocuments {
  if items.length() == 0 {
    match template {
      @provider.RerankingDocuments::TextDocuments(_) =>
        @provider.RerankingDocuments::TextDocuments([])
      @provider.RerankingDocuments::ObjectDocuments(_) =>
        @provider.RerankingDocuments::ObjectDocuments([])
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
        @provider.RerankingDocuments::TextDocuments(values)
      }
      RerankingDocument::ObjectDocument(_) => {
        let values : Array[Json] = []
        for item in items {
          match item.document {
            RerankingDocument::ObjectDocument(value) => values.push(value)
            RerankingDocument::TextDocument(_) => ()
          }
        }
        @provider.RerankingDocuments::ObjectDocuments(values)
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
  model : &RerankingModel,
  documents : RerankingDocuments,
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
    @provider.RerankingDocuments::TextDocuments(values) =>
      @provider.RerankingDocuments::TextDocuments(values.copy())
    @provider.RerankingDocuments::ObjectDocuments(values) =>
      @provider.RerankingDocuments::ObjectDocuments(values.copy())
  }
  if original_documents.length() == 0 {
    return {
      original_documents,
      reranked_documents: reranking_documents_from_items([], original_documents),
      ranking: [],
      usage: Usage::zero(),
      response: ResponseMetadata::new(model_id=model.model_id()),
      provider_metadata: Map([]),
      warnings: [],
    }
  }
  let response = model.rerank(
    RerankingCallOptions::new(
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
    usage: response.usage,
    response: response.response.unwrap_or(
      ResponseMetadata::new(model_id=model.model_id()),
    ),
    provider_metadata: response.provider_metadata,
    warnings: response.warnings,
  }
}

///|
/// Rerank text documents without constructing the representation enum.
pub async fn rerank_text(
  model : &RerankingModel,
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
    RerankingDocuments::text(documents),
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
  model : &RerankingModel,
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

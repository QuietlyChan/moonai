///|
/// Options shared by provider-neutral embedding calls.
pub(all) struct EmbeddingOptions {
  dimensions : Int?
  user : String?
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct normalized embedding options.
pub fn EmbeddingOptions::new(
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> EmbeddingOptions {
  {
    dimensions,
    user,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Result returned by the model layer for one or more values.
pub(all) struct EmbeddingBatchResponse {
  embeddings : Array[Array[Double]]
  usage : Usage
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct an embedding batch response without transport diagnostics.
pub fn EmbeddingBatchResponse::new(
  embeddings : Array[Array[Double]],
  usage : Usage,
) -> EmbeddingBatchResponse {
  {
    embeddings,
    usage,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach diagnostics to an embedding batch result.
pub fn EmbeddingBatchResponse::with_diagnostics(
  self : EmbeddingBatchResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> EmbeddingBatchResponse {
  {
    embeddings: self.embeddings,
    usage: self.usage,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add HTTP metadata to an embedding batch result.
pub fn EmbeddingBatchResponse::with_transport(
  self : EmbeddingBatchResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> EmbeddingBatchResponse {
  {
    embeddings: self.embeddings,
    usage: self.usage,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}

///|
/// Result returned by the single-value `embed` helper.
pub(all) struct EmbeddingResponse {
  embedding : Array[Double]
  usage : Usage
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a single embedding response without transport diagnostics.
pub fn EmbeddingResponse::new(
  embedding : Array[Double],
  usage : Usage,
) -> EmbeddingResponse {
  {
    embedding,
    usage,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

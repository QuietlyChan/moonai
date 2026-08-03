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

///|
/// Embed one text value.
pub async fn embed(
  model : &EmbeddingModel,
  value : String,
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> EmbeddingResponse {
  check_cancellation(cancellation_token)
  let response = model.embed(
    [value],
    EmbeddingOptions::new(
      dimensions?,
      user?,
      headers~,
      provider_options~,
      retry_policy~,
      cancellation_token?,
    ),
  )
  guard response.embeddings.length() == 1 else {
    fail(
      "embedding provider returned \{response.embeddings.length()} embeddings for 1 value",
    )
  }
  {
    embedding: response.embeddings[0],
    usage: response.usage,
    request: response.request,
    response: response.response,
    provider_metadata: copy_provider_metadata(response.provider_metadata),
    warnings: copy_warnings(response.warnings),
  }
}

///|
/// Embed multiple text values, splitting calls at the model's batch limit.
pub async fn embed_many(
  model : &EmbeddingModel,
  values : Array[String],
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> EmbeddingBatchResponse {
  check_cancellation(cancellation_token)
  guard values.length() > 0 else {
    fail("embed_many requires at least one value")
  }
  let max_embeddings_per_call = model.max_embeddings_per_call()
  guard max_embeddings_per_call > 0 else {
    fail("embedding model max_embeddings_per_call must be greater than zero")
  }
  let embeddings : Array[Array[Double]] = []
  let mut usage = Usage::zero()
  let mut first_request : RequestMetadata? = None
  let mut response_metadata : ResponseMetadata? = None
  let mut provider_metadata : Map[String, Json] = Map([])
  let warnings : Array[Warning] = []
  let mut offset = 0
  while offset < values.length() {
    check_cancellation(cancellation_token)
    let remaining = values.length() - offset
    let batch_size = if remaining < max_embeddings_per_call {
      remaining
    } else {
      max_embeddings_per_call
    }
    let batch : Array[String] = []
    for index in offset..<(offset + batch_size) {
      batch.push(values[index])
    }
    let response = model.embed(
      batch,
      EmbeddingOptions::new(
        dimensions?,
        user?,
        headers~,
        provider_options~,
        retry_policy~,
        cancellation_token?,
      ),
    )
    guard response.embeddings.length() == batch_size else {
      fail(
        "embedding provider returned \{response.embeddings.length()} embeddings for \{batch_size} values",
      )
    }
    for embedding in response.embeddings {
      embeddings.push(embedding)
    }
    usage = usage.add(response.usage)
    if first_request is None {
      first_request = response.request
    }
    response_metadata = merge_optional_response_metadata(
      response_metadata,
      response.response,
    )
    provider_metadata = merge_provider_metadata(
      provider_metadata,
      response.provider_metadata,
    )
    for warning in response.warnings {
      warnings.push(warning)
    }
    offset = offset + batch_size
  }
  {
    embeddings,
    usage,
    request: first_request,
    response: response_metadata,
    provider_metadata,
    warnings,
  }
}

///|
/// Camel-case compatibility alias for AI SDK's `embedMany`.
pub async fn embedMany(
  model : &EmbeddingModel,
  values : Array[String],
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> EmbeddingBatchResponse {
  embed_many(
    model,
    values,
    dimensions?,
    user?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// Merge the legacy convenience arguments into the provider-options namespace.
///
/// AI SDK's V4 embedding contract exposes provider options as the extension
/// point. MoonBit keeps `dimensions` and `user` as ergonomic arguments for the
/// moment, but transports them through that same namespaced boundary.
fn embedding_provider_options(
  model : &@provider.EmbeddingModelV4,
  dimensions : Int?,
  user : String?,
  options : Map[String, Json],
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in options.iter2() {
    result[entry.0] = entry.1
  }
  if dimensions is None && user is None {
    return result
  }
  let key = @provider_utils.resolve_provider_options_key(
    model.provider(),
    result,
  )
  let scoped : Map[String, Json] = match result.get(key) {
    Some(Object(values)) => {
      let copied : Map[String, Json] = Map([])
      for entry in values.iter2() {
        copied[entry.0] = entry.1
      }
      copied
    }
    _ => Map([])
  }
  if dimensions is Some(value) && scoped.get("dimensions") is None {
    scoped["dimensions"] = Json::number(value.to_double())
  }
  if user is Some(value) && scoped.get("user") is None {
    scoped["user"] = Json::string(value)
  }
  result[key] = Json::object(scoped)
  result
}

///|
/// Embed one text value through the V4 model contract.
pub async fn embed(
  model : &@provider.EmbeddingModelV4,
  value : String,
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> EmbeddingResponse {
  check_cancellation(cancellation_token)
  let response = model.do_embed(
    @provider.EmbeddingModelV4CallOptions::new(
      [value],
      headers~,
      provider_options=embedding_provider_options(
        model, dimensions, user, provider_options,
      ),
      retry_policy~,
      cancellation_token?,
    ),
  )
  let response = response.to_batch_response()
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
  model : &@provider.EmbeddingModelV4,
  values : Array[String],
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
  max_parallel_calls? : Int,
) -> EmbeddingBatchResponse {
  check_cancellation(cancellation_token)
  guard values.length() > 0 else {
    fail("embed_many requires at least one value")
  }
  let max_embeddings_per_call = match model.max_embeddings_per_call() {
    Some(value) => value
    None => values.length()
  }
  guard max_embeddings_per_call > 0 else {
    fail("embedding model max_embeddings_per_call must be greater than zero")
  }
  let parallel_limit = match max_parallel_calls {
    Some(value) => {
      guard value > 0 else {
        fail("embed_many max_parallel_calls must be greater than zero")
      }
      value
    }
    None => values.length()
  }
  let batch_parallel_limit = if model.supports_parallel_calls() {
    parallel_limit
  } else {
    1
  }
  let embeddings : Array[Array[Double]] = []
  let mut usage = Usage::zero()
  let mut first_request : RequestMetadata? = None
  let mut response_metadata : ResponseMetadata? = None
  let mut provider_metadata : Map[String, Json] = Map([])
  let warnings : Array[Warning] = []
  let mut offset = 0
  while offset < values.length() {
    let tasks : Array[async () -> (Int, @provider.EmbeddingModelV4Result)] = []
    let mut next_offset = offset
    while next_offset < values.length() && tasks.length() < batch_parallel_limit {
      check_cancellation(cancellation_token)
      let remaining = values.length() - next_offset
      let batch_size = if remaining < max_embeddings_per_call {
        remaining
      } else {
        max_embeddings_per_call
      }
      let batch : Array[String] = []
      for index in next_offset..<(next_offset + batch_size) {
        batch.push(values[index])
      }
      let expected_size = batch_size
      tasks.push(() => {
        (
          expected_size,
          model.do_embed(
            @provider.EmbeddingModelV4CallOptions::new(
              batch,
              headers~,
              provider_options=embedding_provider_options(
                model, dimensions, user, provider_options,
              ),
              retry_policy~,
              cancellation_token?,
            ),
          ),
        )
      })
      next_offset = next_offset + batch_size
    }
    let responses = @async.all(tasks)
    for result in responses {
      let (expected_size, response) = result
      let response = response.to_batch_response()
      guard response.embeddings.length() == expected_size else {
        fail(
          "embedding provider returned \{response.embeddings.length()} embeddings for \{expected_size} values",
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
    }
    offset = next_offset
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
/// AI SDK-style camel-case spelling for `embed_many`.
pub async fn embedMany(
  model : &@provider.EmbeddingModelV4,
  values : Array[String],
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
  max_parallel_calls? : Int,
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
    max_parallel_calls?,
  )
}

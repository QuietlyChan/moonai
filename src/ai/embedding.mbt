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
  runtime_context? : Json,
  on_start? : async (EmbedStartEvent) -> Unit,
  on_end? : async (EmbedEndEvent) -> Unit,
) -> EmbeddingResponse {
  check_cancellation(cancellation_token)
  let runtime = runtime_context.unwrap_or(Json::empty_object())
  let call_id = @provider_utils.generate_id()
  match on_start {
    Some(notify) =>
      notify({
        runtime_context: runtime,
        call_id,
        operation_id: "ai.embed",
        provider: model.provider(),
        model_id: model.model_id(),
        values: [value],
        max_retries: retry_policy.max_retries,
        headers: @provider_utils.copy_headers(headers),
        provider_options: @provider.copy_provider_metadata(provider_options),
      }) catch {
        _ => ()
      }
    None => ()
  }
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
  match on_end {
    Some(notify) =>
      notify({
        runtime_context: runtime,
        call_id,
        operation_id: "ai.embed",
        provider: model.provider(),
        model_id: model.model_id(),
        values: [value],
        embeddings: response.embeddings.copy(),
        usage: response.usage,
        warnings: copy_warnings(response.warnings),
        provider_metadata: copy_provider_metadata(response.provider_metadata),
      }) catch {
        _ => ()
      }
    None => ()
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
  runtime_context? : Json,
  on_start? : async (EmbedStartEvent) -> Unit,
  on_end? : async (EmbedEndEvent) -> Unit,
) -> EmbeddingBatchResponse {
  check_cancellation(cancellation_token)
  let runtime = runtime_context.unwrap_or(Json::empty_object())
  let call_id = @provider_utils.generate_id()
  match on_start {
    Some(notify) =>
      notify({
        runtime_context: runtime,
        call_id,
        operation_id: "ai.embedMany",
        provider: model.provider(),
        model_id: model.model_id(),
        values: values.copy(),
        max_retries: retry_policy.max_retries,
        headers: @provider_utils.copy_headers(headers),
        provider_options: @provider.copy_provider_metadata(provider_options),
      }) catch {
        _ => ()
      }
    None => ()
  }
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
  let max_input_bytes_per_call = model.max_input_bytes_per_call()
  let batches = split_embedding_batches(
    values, max_embeddings_per_call, max_input_bytes_per_call,
  )
  let parallel_limit = match max_parallel_calls {
    Some(value) => {
      guard value > 0 else {
        raise invalid_argument(
          parameter="max_parallel_calls",
          value=Json::number(value.to_double()),
          message="max_parallel_calls must be greater than zero",
        )
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
  while offset < batches.length() {
    let tasks : Array[async () -> (Int, @provider.EmbeddingModelV4Result)] = []
    let mut next_offset = offset
    while next_offset < batches.length() &&
          tasks.length() < batch_parallel_limit {
      check_cancellation(cancellation_token)
      let batch = batches[next_offset]
      let expected_size = batch.length()
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
      next_offset = next_offset + 1
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
  match on_end {
    Some(notify) =>
      notify({
        runtime_context: runtime,
        call_id,
        operation_id: "ai.embedMany",
        provider: model.provider(),
        model_id: model.model_id(),
        values: values.copy(),
        embeddings: embeddings.copy(),
        usage,
        warnings: warnings.copy(),
        provider_metadata: @provider.copy_provider_metadata(provider_metadata),
      }) catch {
        _ => ()
      }
    None => ()
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
  runtime_context? : Json,
  on_start? : async (EmbedStartEvent) -> Unit,
  on_end? : async (EmbedEndEvent) -> Unit,
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
    runtime_context?,
    on_start?,
    on_end?,
  )
}

///|
/// Split embedding inputs into batches honoring both the per-call count
/// limit and the optional UTF-8 input-byte budget, in a single pass.
///
/// A single input larger than the byte budget becomes its own batch, matching
/// AI SDK behavior: the request is still attempted once so the provider can
/// reject it with its own diagnostics.
fn split_embedding_batches(
  values : Array[String],
  max_embeddings_per_call : Int,
  max_input_bytes_per_call : Int64?,
) -> Array[Array[String]] raise {
  if max_input_bytes_per_call is Some(limit) {
    guard limit > 0 else {
      fail("embedding model max_input_bytes_per_call must be greater than zero")
    }
  }
  let batches : Array[Array[String]] = []
  let mut current : Array[String] = []
  let mut current_bytes = 0L
  let byte_limit = max_input_bytes_per_call.unwrap_or(-1L)
  for value in values {
    let input_bytes = @utf8.encode(value).length().to_int64()
    let byte_overflow = byte_limit >= 0 &&
      current_bytes + input_bytes > byte_limit
    if current.length() > 0 &&
      (current.length() >= max_embeddings_per_call || byte_overflow) {
      batches.push(current)
      current = []
      current_bytes = 0L
    }
    current.push(value)
    current_bytes = current_bytes + input_bytes
  }
  if current.length() > 0 {
    batches.push(current)
  }
  batches
}

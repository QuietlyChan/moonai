///|
/// Submit a batch of requests through a provider's batch interface.
pub async fn start_batch(
  batch : &BatchV4,
  requests~ : Array[BatchV4Request],
  webhook_url? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4StartResult {
  guard requests.length() > 0 else {
    fail("start_batch requires at least one request")
  }
  batch.do_start_batch(
    BatchV4StartOptions::new(
      requests~,
      webhook_url?,
      call_options=BatchV4CallOptions::new(
        provider_options~,
        headers~,
        cancellation_token?,
      ),
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `start_batch`.
pub async fn startBatch(
  batch : &BatchV4,
  requests~ : Array[BatchV4Request],
  webhook_url? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4StartResult {
  start_batch(
    batch,
    requests~,
    webhook_url?,
    headers~,
    provider_options~,
    cancellation_token?,
  )
}

///|
/// Poll the lifecycle status of one batch.
pub async fn get_batch_status(
  batch : &BatchV4,
  batch_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4Status {
  guard batch_id.trim() != "" else {
    fail("get_batch_status requires a non-empty batch_id")
  }
  batch.do_get_batch_status(
    BatchV4OperationOptions::new(
      batch_id~,
      call_options=BatchV4CallOptions::new(
        provider_options~,
        headers~,
        cancellation_token?,
      ),
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `get_batch_status`.
pub async fn getBatchStatus(
  batch : &BatchV4,
  batch_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4Status {
  get_batch_status(
    batch,
    batch_id~,
    headers~,
    provider_options~,
    cancellation_token?,
  )
}

///|
/// Read the terminal item results of one batch.
pub async fn get_batch_results(
  batch : &BatchV4,
  batch_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> Array[BatchV4ItemResult] {
  guard batch_id.trim() != "" else {
    fail("get_batch_results requires a non-empty batch_id")
  }
  batch.do_get_batch_results(
    BatchV4OperationOptions::new(
      batch_id~,
      call_options=BatchV4CallOptions::new(
        provider_options~,
        headers~,
        cancellation_token?,
      ),
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `get_batch_results`.
pub async fn getBatchResults(
  batch : &BatchV4,
  batch_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> Array[BatchV4ItemResult] {
  get_batch_results(
    batch,
    batch_id~,
    headers~,
    provider_options~,
    cancellation_token?,
  )
}

///|
/// Request cancellation of one batch.
pub async fn cancel_batch(
  batch : &BatchV4,
  batch_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4CancelResult {
  guard batch_id.trim() != "" else {
    fail("cancel_batch requires a non-empty batch_id")
  }
  batch.do_cancel_batch(
    BatchV4OperationOptions::new(
      batch_id~,
      call_options=BatchV4CallOptions::new(
        provider_options~,
        headers~,
        cancellation_token?,
      ),
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `cancel_batch`.
pub async fn cancelBatch(
  batch : &BatchV4,
  batch_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4CancelResult {
  cancel_batch(
    batch,
    batch_id~,
    headers~,
    provider_options~,
    cancellation_token?,
  )
}

///|
/// List batches known to the provider.
pub async fn list_batches(
  batch : &BatchV4,
  limit? : Int,
  cursor? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4ListResult {
  batch.do_list_batches(
    BatchV4ListOptions::new(
      limit?,
      cursor?,
      call_options=BatchV4CallOptions::new(
        provider_options~,
        headers~,
        cancellation_token?,
      ),
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `list_batches`.
pub async fn listBatches(
  batch : &BatchV4,
  limit? : Int,
  cursor? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4ListResult {
  list_batches(
    batch,
    limit?,
    cursor?,
    headers~,
    provider_options~,
    cancellation_token?,
  )
}

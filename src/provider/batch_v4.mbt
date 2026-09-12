///|
/// Modality of one batch request or item result.
pub(all) enum BatchV4Modality {
  BatchModalityText
  BatchModalityImage
} derive(Debug, Eq)

///|
/// Model identifier for one batch request.
pub type BatchV4ModelId = String

///|
/// Normalized lifecycle state of a batch.
pub(all) enum BatchV4State {
  BatchPending
  BatchCompleted
  BatchFailed
} derive(Debug, Eq)

///|
/// Terminal state of one batch request that finished without a result.
pub(all) enum BatchV4TerminatedState {
  BatchCancelled
  BatchExpired
} derive(Debug, Eq)

///|
/// Serializable error information for a batch or batch item.
pub(all) struct BatchV4Error {
  message : String
  error_type : String?
  code : String?
  status_code : Int?
} derive(Debug, Eq)

///|
/// Construct a batch error.
pub fn BatchV4Error::new(
  message~ : String,
  error_type? : String,
  code? : String,
  status_code? : Int,
) -> BatchV4Error {
  { message, error_type, code, status_code, }
}

///|
/// Per-request counts reported by the provider while a batch is running.
pub(all) struct BatchV4RequestCounts {
  total : Int
  pending : Int
  completed : Int
  failed : Int
} derive(Debug, Eq)

///|
/// Construct validated request counts.
pub fn BatchV4RequestCounts::new(
  total~ : Int,
  pending~ : Int,
  completed~ : Int,
  failed~ : Int,
) -> BatchV4RequestCounts raise {
  guard total >= 0 && pending >= 0 && completed >= 0 && failed >= 0 else {
    fail("batch request counts must not be negative")
  }
  { total, pending, completed, failed, }
}

///|
/// Normalized lifecycle status of a batch.
pub(all) struct BatchV4Status {
  state : BatchV4State
  raw_status : String?
  request_counts : BatchV4RequestCounts?
  error : BatchV4Error?
  created_at : String?
  expires_at : String?
  provider_metadata : Map[String, Json]
} derive(Debug)

///|
/// Construct a batch status.
pub fn BatchV4Status::new(
  state~ : BatchV4State,
  raw_status? : String,
  request_counts? : BatchV4RequestCounts,
  error? : BatchV4Error,
  created_at? : String,
  expires_at? : String,
  provider_metadata? : Map[String, Json] = Map([]),
) -> BatchV4Status {
  {
    state,
    raw_status,
    request_counts,
    error,
    created_at,
    expires_at,
    provider_metadata: copy_provider_metadata(provider_metadata),
  }
}

///|
/// Shared call options for batch operations.
pub(all) struct BatchV4CallOptions {
  provider_options : Map[String, Json]
  headers : Map[String, String]
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct batch call options.
pub fn BatchV4CallOptions::new(
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  cancellation_token? : CancellationToken,
) -> BatchV4CallOptions {
  { provider_options, headers, cancellation_token, }
}

///|
/// Options for starting a batch.
pub(all) struct BatchV4StartOptions {
  requests : Array[BatchV4Request]
  webhook_url : String?
  call_options : BatchV4CallOptions
} derive(Debug)

///|
/// Construct batch start options.
pub fn BatchV4StartOptions::new(
  requests~ : Array[BatchV4Request],
  webhook_url? : String,
  call_options? : BatchV4CallOptions = BatchV4CallOptions::new(),
) -> BatchV4StartOptions {
  { requests, webhook_url, call_options, }
}

///|
/// A normalized text generation request within a batch.
pub(all) struct BatchV4TextRequest {
  request_id : String
  model_id : BatchV4ModelId
  prompt : String
  max_output_tokens : Int?
  temperature : Double?
  top_p : Double?
  top_k : Double?
  presence_penalty : Double?
  frequency_penalty : Double?
  seed : Int?
  stop_sequences : Array[String]
  reasoning : LanguageModelV4ReasoningEffort
  response_format : LanguageModelV4ResponseFormat
  tools : Array[LanguageModelV4Tool]
  tool_choice : LanguageModelV4ToolChoice?
  provider_options : Map[String, Json]
} derive(Debug)

///|
/// A normalized image generation request within a batch.
pub(all) struct BatchV4ImageRequest {
  request_id : String
  model_id : BatchV4ModelId
  prompt : String
  n : Int?
  size : String?
  aspect_ratio : String?
  seed : Int?
  files : Array[ImageModelV4File]
  mask : ImageModelV4File?
  provider_options : Map[String, Json]
} derive(Debug)

///|
/// One request in a batch, discriminated by modality.
pub(all) enum BatchV4Request {
  BatchTextRequest(BatchV4TextRequest)
  BatchImageRequest(BatchV4ImageRequest)
} derive(Debug)

///|
/// Return the application-provided correlation id of a batch request.
pub fn BatchV4Request::request_id(self : BatchV4Request) -> String {
  match self {
    BatchTextRequest(request) => request.request_id
    BatchImageRequest(request) => request.request_id
  }
}

///|
/// Per-request warning emitted while starting or reading a batch.
pub(all) struct BatchV4RequestWarning {
  request_id : String?
  warning : Warning
} derive(Debug)

///|
/// Result of starting a batch.
pub(all) struct BatchV4StartResult {
  batch_id : String
  status : BatchV4Status
  warnings : Array[BatchV4RequestWarning]
} derive(Debug)

///|
/// Construct a batch start result.
pub fn BatchV4StartResult::new(
  batch_id~ : String,
  status~ : BatchV4Status,
  warnings? : Array[BatchV4RequestWarning] = [],
) -> BatchV4StartResult {
  { batch_id, status, warnings: warnings.copy(), }
}

///|
/// Options for a batch status, results, or cancel operation.
pub(all) struct BatchV4OperationOptions {
  batch_id : String
  call_options : BatchV4CallOptions
} derive(Debug)

///|
/// Construct batch operation options.
pub fn BatchV4OperationOptions::new(
  batch_id~ : String,
  call_options? : BatchV4CallOptions = BatchV4CallOptions::new(),
) -> BatchV4OperationOptions {
  { batch_id, call_options, }
}

///|
/// Result of requesting cancellation of a batch.
pub(all) struct BatchV4CancelResult {
  provider_metadata : Map[String, Json]
} derive(Debug)

///|
/// Construct a batch cancel result.
pub fn BatchV4CancelResult::new(
  provider_metadata? : Map[String, Json] = Map([]),
) -> BatchV4CancelResult {
  { provider_metadata: copy_provider_metadata(provider_metadata), }
}

///|
/// Options for listing batches.
pub(all) struct BatchV4ListOptions {
  limit : Int?
  cursor : String?
  call_options : BatchV4CallOptions
} derive(Debug)

///|
/// Construct batch list options.
pub fn BatchV4ListOptions::new(
  limit? : Int,
  cursor? : String,
  call_options? : BatchV4CallOptions = BatchV4CallOptions::new(),
) -> BatchV4ListOptions {
  { limit, cursor, call_options, }
}

///|
/// One batch returned by a list operation.
pub(all) struct BatchV4ListItem {
  batch_id : String
  status : BatchV4Status
} derive(Debug)

///|
/// Result of listing batches.
pub(all) struct BatchV4ListResult {
  batches : Array[BatchV4ListItem]
  next_cursor : String?
  provider_metadata : Map[String, Json]
} derive(Debug)

///|
/// Construct a batch list result.
pub fn BatchV4ListResult::new(
  batches~ : Array[BatchV4ListItem],
  next_cursor? : String,
  provider_metadata? : Map[String, Json] = Map([]),
) -> BatchV4ListResult {
  {
    batches: batches.copy(),
    next_cursor,
    provider_metadata: copy_provider_metadata(provider_metadata),
  }
}

///|
/// Payload of a succeeded batch item, discriminated by modality.
pub(all) enum BatchV4ItemPayload {
  BatchTextResult(LanguageModelV4GenerateResult)
  BatchImageResult(ImageModelV4Result)
} derive(Debug)

///|
/// Terminal result for one request in a batch.
pub(all) enum BatchV4ItemResult {
  BatchItemSucceeded(
    id~ : String,
    modality~ : BatchV4Modality,
    result~ : BatchV4ItemPayload,
    provider_metadata~ : Map[String, Json]
  )
  BatchItemFailed(
    id~ : String,
    modality~ : BatchV4Modality,
    error~ : BatchV4Error,
    provider_metadata~ : Map[String, Json]
  )
  BatchItemTerminated(
    id~ : String,
    modality~ : BatchV4Modality,
    state~ : BatchV4TerminatedState,
    error~ : BatchV4Error?,
    provider_metadata~ : Map[String, Json]
  )
} derive(Debug)

///|
/// Return the application-provided correlation id of a batch item result.
pub fn BatchV4ItemResult::id(self : BatchV4ItemResult) -> String {
  match self {
    BatchItemSucceeded(id~, ..) => id
    BatchItemFailed(id~, ..) => id
    BatchItemTerminated(id~, ..) => id
  }
}

///|
/// Specification for a batch interface implementing batch version 4
/// (AI SDK BatchV4).
///
/// Batch item results are delivered as a buffered array; the upstream
/// contract streams them incrementally, which moonai backends surface once
/// the provider layer grows an incremental result channel.
pub(open) trait BatchV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn supported_urls(Self) -> Array[SupportedUrlRule]
  async fn do_start_batch(Self, BatchV4StartOptions) -> BatchV4StartResult
  async fn do_get_batch_status(Self, BatchV4OperationOptions) -> BatchV4Status
  async fn do_get_batch_results(Self, BatchV4OperationOptions) -> Array[
    BatchV4ItemResult,
  ]
  async fn do_cancel_batch(Self, BatchV4OperationOptions) -> BatchV4CancelResult
  async fn do_list_batches(Self, BatchV4ListOptions) -> BatchV4ListResult
}

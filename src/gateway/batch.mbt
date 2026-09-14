///|
/// The AI Gateway batch surface: durable text-generation batches through
/// `POST /batch/{start|status|results}`. The returned batchId is the
/// Gateway job id — provider-native batch ids stay server-side. Cancel and
/// list are not part of the Gateway batch protocol.
struct GatewayBatch {
  provider_name : String
  api_key : String
  base_url : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn gateway_batch_value(
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewayBatch {
  {
    provider_name: "gateway.batch",
    api_key,
    base_url,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn GatewayBatch::batch_headers(
  self : GatewayBatch,
  extra~ : Map[String, String],
  model_id~ : String?,
  idempotency_key~ : String?,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="AI_GATEWAY_API_KEY",
    description="AI Gateway",
  )
  let resolved = @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          ("Authorization", "Bearer \{api_key}"),
          ("Content-Type", "application/json"),
          ("accept", "application/json"),
        ]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/gateway/\{VERSION}"],
  )
  match model_id {
    Some(id) => resolved["ai-model-id"] = id
    None => ()
  }
  match idempotency_key {
    Some(key) => resolved["idempotency-key"] = key
    None => ()
  }
  resolved
}

///|
fn GatewayBatch::batch_url(self : GatewayBatch, path~ : String) -> String {
  @provider_utils.append_path(self.base_url, "/batch/\{path}")
}

///|
/// Validate a text batch: every request must be a text request for the same
/// model; return that model id.
fn gateway_assert_text_batch(
  requests : Array[@provider.BatchV4Request],
) -> String raise {
  guard requests.length() > 0 else {
    raise @provider.InvalidArgumentError(
      argument="requests",
      message="batch requires at least one request",
    )
  }
  let model_id = match requests[0] {
    @provider.BatchTextRequest(text_request) => text_request.model_id
    @provider.BatchImageRequest(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="batch request type: image",
      )
  }
  for request in requests {
    match request {
      @provider.BatchTextRequest(text_request) =>
        if text_request.model_id != model_id {
          raise @provider.InvalidArgumentError(
            argument="requests",
            message="The AI Gateway Batch API requires all requests in a batch to use the same model. Found \"\{model_id}\" and \"\{text_request.model_id}\".",
          )
        }
      @provider.BatchImageRequest(_) =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="batch request type: image",
        )
    }
  }
  model_id
}

///|
/// Extract the optional gateway idempotency key from
/// `providerOptions.gateway.idempotencyKey` and the remaining forwarded
/// provider options with that key omitted.
fn gateway_batch_idempotency(
  provider_options~ : Map[String, Json],
) -> (String?, Map[String, Json]) {
  let forwarded : Map[String, Json] = Map([])
  let mut key : String? = None
  for entry in provider_options.iter2() {
    match entry.1 {
      Object(options) =>
        match options.get("idempotencyKey") {
          Some(String(idempotency)) if entry.0 == "gateway" => {
            key = Some(idempotency)
            let remaining : Map[String, Json] = Map([])
            for field in options.iter2() {
              if field.0 != "idempotencyKey" {
                remaining[field.0] = field.1
              }
            }
            forwarded[entry.0] = Json::object(remaining)
          }
          _ => forwarded[entry.0] = entry.1
        }
      _ => forwarded[entry.0] = entry.1
    }
  }
  (key, forwarded)
}

///|
/// Encode one text batch request as the gateway request entry.
fn gateway_encode_batch_request(
  request : @provider.BatchV4Request,
) -> Json raise {
  match request {
    @provider.BatchTextRequest(text_request) => {
      let options : Map[String, Json] = Map([])
      if text_request.max_output_tokens is Some(value) {
        options["maxOutputTokens"] = Json::number(value.to_double())
      }
      if text_request.temperature is Some(value) {
        options["temperature"] = Json::number(value)
      }
      if text_request.top_p is Some(value) {
        options["topP"] = Json::number(value)
      }
      if text_request.stop_sequences.length() > 0 {
        options["stopSequences"] = Json::array(
          [
            for value in text_request.stop_sequences => Json::string(value)
          ],
        )
      }
      let entry : Map[String, Json] = Map([
        ("id", Json::string(text_request.request_id)),
        ("type", Json::string("text")),
        ("modelId", Json::string(text_request.model_id)),
        ("options", Json::object(options)),
      ])
      Json::object(entry)
    }
    @provider.BatchImageRequest(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="batch request type: image",
      )
  }
}

///|
/// Map the gateway status payload onto the shared BatchV4Status.
fn convert_gateway_batch_status(body : Json) -> @provider.BatchV4Status raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  guard body is Object(fields) else {
    fail("gateway batch status response is not an object")
  }
  let raw_status = match fields.get("status") {
    Some(String(status)) => Some(status)
    _ => None
  }
  let state = match raw_status {
    Some("completed") => @provider.BatchCompleted
    Some("failed") => @provider.BatchFailed
    _ => @provider.BatchPending
  }
  let counts : @provider.BatchV4RequestCounts? = match
    fields.get("requestCounts") {
    Some(Object(count_fields)) => {
      let total = match count_fields.get("total") {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
      let pending = match count_fields.get("pending") {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
      let completed = match count_fields.get("completed") {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
      let failed = match count_fields.get("failed") {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
      Some(
        @provider.BatchV4RequestCounts::new(
          total~,
          pending~,
          completed~,
          failed~,
        ),
      )
    }
    _ => None
  }
  let batch_error : @provider.BatchV4Error? = match fields.get("error") {
    Some({ "message": String(message), .. }) =>
      Some(@provider.BatchV4Error::new(message~, error_type="", code=""))
    _ => None
  }
  let created_at = match fields.get("createdAt") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let expires_at = match fields.get("expiresAt") {
    Some(String(value)) => Some(value)
    _ => None
  }
  {
    state,
    raw_status,
    request_counts: counts,
    error: batch_error,
    created_at,
    expires_at,
    provider_metadata: Map([]),
  }
}

///|
pub impl @provider.BatchV4 for GatewayBatch with fn specification_version(_self) -> String {
  "v4"
}

///|
pub impl @provider.BatchV4 for GatewayBatch with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.BatchV4 for GatewayBatch with fn supported_urls(_self) -> Array[
  @provider.SupportedUrlRule,
] {
  [@provider.SupportedUrlRule::all("*/*")]
}

///|
pub impl @provider.BatchV4 for GatewayBatch with fn do_start_batch(
  self,
  options,
) -> @provider.BatchV4StartResult raise {
  let model_id = gateway_assert_text_batch(options.requests)
  let encoded : Array[Json] = []
  for request in options.requests {
    encoded.push(gateway_encode_batch_request(request))
  }
  let (idempotency_key, forwarded) = gateway_batch_idempotency(
    provider_options=options.call_options.provider_options,
  )
  let fields : Map[String, Json] = Map([("requests", Json::array(encoded))])
  if options.webhook_url is Some(url) {
    fields["callbackUrl"] = Json::string(url)
  }
  if forwarded.length() > 0 {
    fields["providerOptions"] = Json::object(forwarded)
  }
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.batch_url(path="start"),
    headers=self.batch_headers(
      extra=options.call_options.headers,
      model_id=Some(model_id),
      idempotency_key~,
    ),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let batch_id = match response.value {
    { "batchId": String(batch_id), .. } => batch_id
    _ => fail("gateway batch start response missing batchId")
  }
  @provider.BatchV4StartResult::new(
    batch_id~,
    status=convert_gateway_batch_status(response.value),
    warnings=gateway_decode_batch_request_warnings(response.value),
  )
}

///|
/// Wrap shared warnings as batch request warnings (request_id absent).
fn gateway_decode_batch_request_warnings(
  value : Json,
) -> Array[@provider.BatchV4RequestWarning] {
  let warnings : Array[@provider.BatchV4RequestWarning] = []
  for warning in gateway_decode_warnings(Some(value)) {
    warnings.push(@provider.BatchV4RequestWarning::{
      request_id: None,
      warning,
    })
  }
  warnings
}

///|
pub impl @provider.BatchV4 for GatewayBatch with fn do_get_batch_status(
  self,
  options,
) -> @provider.BatchV4Status raise {
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.batch_url(path="status"),
    headers=self.batch_headers(
      extra=options.call_options.headers,
      model_id=None,
      idempotency_key=None,
    ),
    body=Json::object(Map([("batchId", Json::string(options.batch_id))])),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  convert_gateway_batch_status(response.value)
}

///|
/// Split an NDJSON payload into per-line JSON values (empty lines skipped).
fn gateway_split_ndjson(data : Bytes) -> Array[Json] raise {
  let lines : Array[Json] = []
  let total = data.length()
  let mut start = 0
  let mut i = 0
  while i < total {
    if data[i] == b'
' {
      let mut line_end = i
      if i > start && data[i - 1] == b'
' {
        line_end = i - 1
      }
      if line_end > start {
        let slice = data[start:line_end]
        let parsed = @json.parse(@utf8.decode(slice)) catch {
          _ => return fail("gateway batch results contain an invalid JSON line")
        }
        lines.push(parsed)
      }
      start = i + 1
    }
    i = i + 1
  }
  if total > start {
    let slice = data[start:total]
    let parsed = @json.parse(@utf8.decode(slice)) catch {
      _ => return fail("gateway batch results contain an invalid JSON line")
    }
    lines.push(parsed)
  }
  lines
}

///|
/// Decode one gateway batch result line: id + status minimum; succeeded
/// lines carry a text result in result.textContent.
fn decode_gateway_batch_result_line(
  line : Json,
) -> @provider.BatchV4ItemResult? {
  let id = match line {
    { "id": String(id), .. } => id
    _ => return None
  }
  let status = match line {
    { "status": String(status), .. } => status
    _ => return None
  }
  let metadata : Map[String, Json] = match line {
    { "providerMetadata": Object(fields), .. } => fields
    _ => Map([])
  }
  match status {
    "succeeded" => {
      let text = match line {
        { "result": { "textContent": String(value), .. }, .. } => value
        _ => ""
      }
      let text_output : @provider.LanguageModelV4Content = @provider.V4TextOutput({
          text,
          provider_metadata: Map([]),
        },
      )
      let text_result : @provider.LanguageModelV4GenerateResult = {
        content: [text_output],
        finish_reason: { unified: @provider.V4FinishStop, raw: None, },
        usage: @provider.LanguageModelV4Usage::unknown(),
        provider_metadata: metadata,
        request: None,
        response: None,
        warnings: [],
      }
      Some(
        @provider.BatchItemSucceeded(
          id~,
          modality=@provider.BatchModalityText,
          result=@provider.BatchTextResult(text_result),
          provider_metadata=metadata,
        ),
      )
    }
    "failed" =>
      Some(
        @provider.BatchItemFailed(
          id~,
          modality=@provider.BatchModalityText,
          error=@provider.BatchV4Error::new(
            message="request failed",
            error_type="",
            code="",
          ),
          provider_metadata=metadata,
        ),
      )
    _ => None
  }
}

///|
pub impl @provider.BatchV4 for GatewayBatch with fn do_get_batch_results(
  self,
  options,
) -> Array[@provider.BatchV4ItemResult] raise {
  let response = @provider_utils.post_json_binary(
    provider_name=self.provider_name,
    url=self.batch_url(path="results"),
    headers=self.batch_headers(
      extra=options.call_options.headers,
      model_id=None,
      idempotency_key=None,
    ),
    body=Json::object(Map([("batchId", Json::string(options.batch_id))])),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let lines = gateway_split_ndjson(response.value)
  let results : Array[@provider.BatchV4ItemResult] = []
  for line in lines {
    match decode_gateway_batch_result_line(line) {
      Some(result) => results.push(result)
      None => ()
    }
  }
  results
}

///|
/// Cancel is not part of the Gateway batch protocol.
pub impl @provider.BatchV4 for GatewayBatch with fn do_cancel_batch(
  _self,
  _options,
) -> @provider.BatchV4CancelResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="gateway batch cancel",
  )
}

///|
/// List is not part of the Gateway batch protocol.
pub impl @provider.BatchV4 for GatewayBatch with fn do_list_batches(
  _self,
  _options,
) -> @provider.BatchV4ListResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="gateway batch list",
  )
}

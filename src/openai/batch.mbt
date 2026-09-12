///|
/// Official OpenAI Batches API implementation (/v1/batches).
///
/// Text requests are serialized to a JSONL input file, uploaded through the
/// Files API with the `batch` purpose, and submitted as one chat-completions
/// batch. Image requests target `/v1/images/generations`. Mixing modalities
/// in one batch is rejected because an OpenAI batch has a single endpoint.
priv struct OpenAIBatch {
  provider_name : String
  base_url : String
  api_key : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
  files : OpenAIFiles
}

///|
fn openai_batch(
  provider_name~ : String,
  base_url~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAIBatch {
  {
    provider_name: "\{provider_name}.batch",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
    files: openai_files(
      provider_name~,
      base_url~,
      api_key~,
      headers~,
      idle_timeout_ms~,
      http_transport~,
    ),
  }
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn specification_version(
  _self : OpenAIBatch,
) -> String {
  "v4"
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn provider(self : OpenAIBatch) -> String {
  self.provider_name
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn supported_urls(
  _self : OpenAIBatch,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
fn OpenAIBatch::batches_url(self : OpenAIBatch) -> String {
  @provider_utils.append_path(self.base_url, "/batches")
}

///|
fn OpenAIBatch::batch_url(self : OpenAIBatch, batch_id : String) -> String {
  @provider_utils.append_path(
    self.batches_url(),
    "/\{@provider_utils.encode_path_segment(batch_id)}",
  )
}

///|
fn OpenAIBatch::request_headers(
  self : OpenAIBatch,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/openai/\{VERSION}"],
  )
}

///|
fn openai_batch_endpoint(modality : @provider.BatchV4Modality) -> String {
  match modality {
    @provider.BatchModalityText => "/v1/chat/completions"
    @provider.BatchModalityImage => "/v1/images/generations"
  }
}

///|
/// Serialize one chat request body for a JSONL batch line.
fn openai_batch_chat_body(request : @provider.BatchV4TextRequest) -> Json raise {
  let warnings : Array[@provider.Warning] = []
  let body : Map[String, Json] = Map([
    ("model", Json::string(request.model_id)),
    (
      "messages",
      Json::array([
        Json::object(
          Map([
            ("role", Json::string("user")),
            ("content", Json::string(request.prompt)),
          ]),
        ),
      ]),
    ),
  ])
  if request.max_output_tokens is Some(value) {
    body["max_completion_tokens"] = Json::number(value.to_double())
  }
  if request.temperature is Some(value) {
    body["temperature"] = Json::number(value)
  }
  if request.top_p is Some(value) {
    body["top_p"] = Json::number(value)
  }
  if request.presence_penalty is Some(value) {
    body["presence_penalty"] = Json::number(value)
  }
  if request.frequency_penalty is Some(value) {
    body["frequency_penalty"] = Json::number(value)
  }
  if request.seed is Some(value) {
    body["seed"] = Json::number(value.to_double())
  }
  if request.stop_sequences.length() > 0 {
    body["stop"] = Json::array(
      [
        for value in request.stop_sequences => Json::string(value)
      ],
    )
  }
  for tool in request.tools {
    match openai_v4_chat_tool(tool, warnings) {
      Some(_) => ()
      None => ()
    }
  }
  match request.response_format {
    @provider.V4ResponseText => ()
    @provider.V4ResponseJson(_) =>
      body["response_format"] = { "type": "json_object" }
  }
  Json::object(body)
}

///|
/// Serialize one image request body for a JSONL batch line.
fn openai_batch_image_body(request : @provider.BatchV4ImageRequest) -> Json {
  let body : Map[String, Json] = Map([
    ("model", Json::string(request.model_id)),
    ("prompt", Json::string(request.prompt)),
  ])
  if request.n is Some(value) {
    body["n"] = Json::number(value.to_double())
  }
  if request.size is Some(value) {
    body["size"] = Json::string(value)
  }
  Json::object(body)
}

///|
fn openai_batch_json_line(request : @provider.BatchV4Request) -> String raise {
  let (custom_id, endpoint, body) = match request {
    @provider.BatchTextRequest(request) =>
      (
        request.request_id,
        openai_batch_endpoint(@provider.BatchModalityText),
        openai_batch_chat_body(request),
      )
    @provider.BatchImageRequest(request) =>
      (
        request.request_id,
        openai_batch_endpoint(@provider.BatchModalityImage),
        openai_batch_image_body(request),
      )
  }
  (
    { "custom_id": custom_id, "method": "POST", "url": endpoint, "body": body } :
    Json).stringify()
}

///|
fn openai_batch_modality(
  requests : Array[@provider.BatchV4Request],
) -> @provider.BatchV4Modality raise {
  guard requests.length() > 0 else {
    fail("a batch requires at least one request")
  }
  let first = match requests[0] {
    @provider.BatchTextRequest(_) => @provider.BatchModalityText
    @provider.BatchImageRequest(_) => @provider.BatchModalityImage
  }
  for request in requests {
    let other = match request {
      @provider.BatchTextRequest(_) => @provider.BatchModalityText
      @provider.BatchImageRequest(_) => @provider.BatchModalityImage
    }
    guard other == first else {
      fail(
        "OpenAI batches accept a single endpoint; text and image requests cannot be mixed",
      )
    }
  }
  first
}

///|
fn openai_batch_status(json : Json) -> @provider.BatchV4Status {
  let raw_status = @provider_utils.json_string_field(json, "status")
  let state = match raw_status {
    Some("completed") => @provider.BatchCompleted
    Some("failed") | Some("expired") | Some("cancelled") =>
      @provider.BatchFailed
    _ => @provider.BatchPending
  }
  let request_counts = match json {
    {
      "request_counts": {
        "total": Number(total, ..),
        "pending": Number(pending, ..),
        "completed": Number(completed, ..),
        "failed": Number(failed, ..),
        ..
      },
      ..
    } =>
      Some(
        (
          {
            total: total.to_int(),
            pending: pending.to_int(),
            completed: completed.to_int(),
            failed: failed.to_int(),
          } : @provider.BatchV4RequestCounts),
      )
    _ => None
  }
  let error_type = match json {
    { "error": { "type": String(kind), .. }, .. } => Some(kind)
    _ => None
  }
  let error = match json {
    { "error": { "message": String(message), .. }, .. } =>
      Some(@provider.BatchV4Error::new(message~, error_type?))
    _ => None
  }
  @provider.BatchV4Status::new(
    state~,
    raw_status?,
    request_counts?,
    error?,
    created_at?=@provider_utils.json_string_field(json, "created_at"),
    expires_at?=@provider_utils.json_string_field(json, "expires_at"),
    provider_metadata=openai_files_provider_metadata(json),
  )
}

///|
async fn OpenAIBatch::upload_input_file(
  self : OpenAIBatch,
  requests : Array[@provider.BatchV4Request],
) -> String {
  let lines : Array[String] = []
  for request in requests {
    lines.push(openai_batch_json_line(request))
  }
  let jsonl = lines.join("\n")
  let upload = self.files.upload(
    @provider.FilesV4UploadFileCallOptions::new(
      data=@provider.UploadFileData::text(jsonl),
      media_type="application/jsonl",
      filename="batch-input.jsonl",
      provider_options=OpenAIFilesOptions::new(purpose="batch").to_provider_options(),
    ),
  )
  let file_id = upload.provider_reference.get("openai")
  option_or_fail(file_id, message="uploaded batch input file id")
}

///|
fn option_or_fail(value : String?, message~ : String) -> String raise {
  match value {
    Some(id) => id
    None => fail("\{message} is missing")
  }
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn do_start_batch(
  self : OpenAIBatch,
  options : @provider.BatchV4StartOptions,
) -> @provider.BatchV4StartResult raise {
  let modality = openai_batch_modality(options.requests)
  let input_file_id = self.upload_input_file(options.requests)
  let body : Map[String, Json] = Map([
    ("input_file_id", Json::string(input_file_id)),
    ("endpoint", Json::string(openai_batch_endpoint(modality))),
    ("completion_window", Json::string("24h")),
  ])
  if options.webhook_url is Some(url) {
    body["webhook_url"] = Json::string(url)
  }
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.batches_url(),
    headers=self.request_headers(),
    body=Json::object(body),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let json = response.value
  let batch_id = @provider_utils.json_string_field(json, "id").unwrap_or("")
  @provider.BatchV4StartResult::new(batch_id~, status=openai_batch_status(json))
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn do_get_batch_status(
  self : OpenAIBatch,
  options : @provider.BatchV4OperationOptions,
) -> @provider.BatchV4Status raise {
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=self.batch_url(options.batch_id),
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  openai_batch_status(response.value)
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn do_get_batch_results(
  self : OpenAIBatch,
  options : @provider.BatchV4OperationOptions,
) -> Array[@provider.BatchV4ItemResult] raise {
  // Resolve the output file through the batch status.
  let status_response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=self.batch_url(options.batch_id),
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let output_file_id = @provider_utils.json_string_field(
    status_response.value,
    "output_file_id",
  )
  guard output_file_id is Some(file_id) else { return [] }
  let content = @provider_utils.get_bytes(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.batch_url(file_id), "/content"),
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    transport=self.http_transport,
  )
  let payload = @utf8.decode(content.value)
  let results : Array[@provider.BatchV4ItemResult] = []
  for line in payload.split("\n") {
    let trimmed = line.trim()
    guard trimmed != "" else { continue }
    let json = @json.parse(trimmed) catch { _ => continue }
    let request_id = @provider_utils.json_string_field(json, "custom_id").unwrap_or(
      "",
    )
    match json {
      {
        "response": {
          "body": { "choices": [_choice, ..], .. } as choice_body,
          ..
        },
        ..
      } => {
        let decoded = decode_openai_chat_response(
          choice_body,
          self.provider_name,
          () => "",
        )
        let generate_result : @provider.LanguageModelV4GenerateResult = {
          content: decoded.content,
          finish_reason: decoded.finish_reason,
          usage: decoded.usage,
          provider_metadata: decoded.provider_metadata,
          request: None,
          response: None,
          warnings: [],
        }
        results.push(
          @provider.BatchItemSucceeded(
            id=request_id,
            modality=@provider.BatchModalityText,
            result=@provider.BatchTextResult(generate_result),
            provider_metadata=decoded.provider_metadata,
          ),
        )
      }
      { "response": { "status_code": Number(code, ..), .. }, .. } =>
        results.push(
          @provider.BatchItemFailed(
            id=request_id,
            modality=@provider.BatchModalityText,
            error=@provider.BatchV4Error::new(
              message="Request failed with status \{code.to_int()}",
              status_code=code.to_int(),
            ),
            provider_metadata=Map([]),
          ),
        )
      { "error": { "message": String(message), .. }, .. } =>
        results.push(
          @provider.BatchItemFailed(
            id=request_id,
            modality=@provider.BatchModalityText,
            error=@provider.BatchV4Error::new(message~),
            provider_metadata=Map([]),
          ),
        )
      _ => ()
    }
  }
  results
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn do_cancel_batch(
  self : OpenAIBatch,
  options : @provider.BatchV4OperationOptions,
) -> @provider.BatchV4CancelResult raise {
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.batch_url(options.batch_id),
    headers=self.request_headers(),
    body={ "status": "cancelled" },
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  @provider.BatchV4CancelResult::new(
    provider_metadata=openai_files_provider_metadata(response.value),
  )
}

///|
impl @provider.BatchV4 for OpenAIBatch with fn do_list_batches(
  self : OpenAIBatch,
  options : @provider.BatchV4ListOptions,
) -> @provider.BatchV4ListResult raise {
  let query_params : Map[String, String] = Map([])
  if options.limit is Some(limit) {
    query_params["limit"] = limit.to_string()
  }
  if options.cursor is Some(cursor) {
    query_params["after"] = cursor
  }
  let url = @provider_utils.append_query(self.batches_url(), query_params)
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url~,
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let batches : Array[@provider.BatchV4ListItem] = []
  let mut next_cursor : String? = None
  match response.value {
    { "data": Array(items), "has_more": True, .. } => {
      for item in items {
        batches.push({
          batch_id: @provider_utils.json_string_field(item, "id").unwrap_or(""),
          status: openai_batch_status(item),
        })
      }
      let mut last : String? = None
      for item in items {
        match @provider_utils.json_string_field(item, "id") {
          Some(id) => last = Some(id)
          None => ()
        }
      }
      next_cursor = last
    }
    { "data": Array(items), .. } =>
      for item in items {
        batches.push({
          batch_id: @provider_utils.json_string_field(item, "id").unwrap_or(""),
          status: openai_batch_status(item),
        })
      }
    _ => ()
  }
  @provider.BatchV4ListResult::new(batches~, next_cursor?)
}

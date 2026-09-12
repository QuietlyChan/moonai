///|
/// Official Anthropic Message Batches API implementation
/// (/v1/messages/batches).
///
/// Text requests are prepared with the same request builder used for
/// synchronous calls and submitted as `{ custom_id, params }` entries.
/// Image requests are rejected: Anthropic Message Batches only accepts
/// message requests.
priv struct AnthropicBatch {
  provider_name : String
  base_url : String
  api_key : String
  auth_token : String
  api_key_environment_variable : String?
  anthropic_version : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
  id_generator : @provider_utils.IdGenerator
}

///|
fn anthropic_batch(
  provider_name~ : String,
  base_url~ : String,
  api_key~ : String,
  auth_token~ : String,
  api_key_environment_variable~ : String?,
  anthropic_version~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> AnthropicBatch {
  {
    provider_name: "\{provider_name}.batch",
    base_url,
    api_key,
    auth_token,
    api_key_environment_variable,
    anthropic_version,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
    id_generator,
  }
}

///|
fn AnthropicBatch::batches_url(self : AnthropicBatch, path : String) -> String {
  @provider_utils.append_path(self.base_url, "/v1/messages/batches" + path)
}

///|
fn AnthropicBatch::request_headers(
  self : AnthropicBatch,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["anthropic-version"] = self.anthropic_version
  headers["anthropic-beta"] = "message-batches-2024-09-24"
  for
    entry in anthropic_authentication_headers(
      self.api_key,
      self.auth_token,
      self.api_key_environment_variable,
    ).iter2() {
    let (key, value) = entry
    headers[key] = value
  }
  let merged = @provider_utils.merge_headers(headers, self.headers)
  merged["anthropic-beta"] = "message-batches-2024-09-24"
  @provider_utils.with_user_agent_suffix(merged, ["moonai/anthropic/\{VERSION}"])
}

///|
fn put_optional_string(
  fields : Map[String, Json],
  key~ : String,
  value~ : String?,
) -> Unit {
  if value is Some(text) {
    fields[key] = Json::string(text)
  }
}

///|
fn anthropic_batch_state(processing_status : String) -> @provider.BatchV4State {
  match processing_status {
    "ended" => @provider.BatchCompleted
    _ => @provider.BatchPending
  }
}

///|
fn anthropic_batch_status(json : Json) -> @provider.BatchV4Status {
  let processing_status = @provider_utils.json_string_field(
    json, "processing_status",
  ).unwrap_or("")
  let state = anthropic_batch_state(processing_status)
  let request_counts = match json {
    {
      "request_counts": {
        "processing": Number(processing, ..),
        "succeeded": Number(succeeded, ..),
        "errored": Number(errored, ..),
        "canceled": Number(canceled, ..),
        "expired": Number(expired, ..),
        ..
      },
      ..
    } => {
      let counts : @provider.BatchV4RequestCounts = {
        total: processing.to_int() +
        succeeded.to_int() +
        errored.to_int() +
        canceled.to_int() +
        expired.to_int(),
        pending: processing.to_int(),
        completed: succeeded.to_int(),
        failed: errored.to_int() + canceled.to_int() + expired.to_int(),
      }
      Some(counts)
    }
    _ => None
  }
  let anthropic_details : Map[String, Json] = Map([])
  put_optional_string(
    anthropic_details,
    key="archived_at",
    value=@provider_utils.json_string_field(json, "archived_at"),
  )
  put_optional_string(
    anthropic_details,
    key="cancel_initiated_at",
    value=@provider_utils.json_string_field(json, "cancel_initiated_at"),
  )
  put_optional_string(
    anthropic_details,
    key="ended_at",
    value=@provider_utils.json_string_field(json, "ended_at"),
  )
  match json {
    { "request_counts": value, .. } =>
      anthropic_details["request_counts"] = value
    _ => ()
  }
  put_optional_string(
    anthropic_details,
    key="results_url",
    value=@provider_utils.json_string_field(json, "results_url"),
  )
  let metadata : Map[String, Json] = Map([
    ("anthropic", Json::object(anthropic_details)),
  ])
  @provider.BatchV4Status::new(
    state~,
    raw_status=processing_status,
    request_counts?,
    created_at?=@provider_utils.json_string_field(json, "created_at"),
    expires_at?=@provider_utils.json_string_field(json, "expires_at"),
    provider_metadata=metadata,
  )
}

///|
fn AnthropicBatch::text_call_options(
  _self : AnthropicBatch,
  request : @provider.BatchV4TextRequest,
) -> @provider.LanguageModelV4CallOptions {
  let prompt : @provider.LanguageModelV4Prompt = @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptText(text=request.prompt, provider_options=Map([])),
        ],
        provider_options=Map([]),
      ),
    ],
  )
  @provider.LanguageModelV4CallOptions::new(
    prompt,
    tools=request.tools,
    tool_choice?=request.tool_choice,
    response_format=request.response_format,
    reasoning=request.reasoning,
    max_output_tokens?=request.max_output_tokens,
    temperature?=request.temperature,
    top_p?=request.top_p,
    top_k?=request.top_k,
    frequency_penalty?=request.frequency_penalty,
    presence_penalty?=request.presence_penalty,
    seed?=request.seed,
    stop_sequences=request.stop_sequences,
    provider_options=request.provider_options,
  )
}

///|
async fn AnthropicBatch::post(
  self : AnthropicBatch,
  url~ : String,
  body~ : Json,
  options : @provider.BatchV4OperationOptions,
) -> Json {
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url~,
    headers=self.request_headers(),
    body~,
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=anthropic_error_message,
    transport=self.http_transport,
  )
  response.value
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn specification_version(
  _self : AnthropicBatch,
) -> String {
  "v4"
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn provider(
  self : AnthropicBatch,
) -> String {
  self.provider_name
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn supported_urls(
  _self : AnthropicBatch,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn do_start_batch(
  self : AnthropicBatch,
  options : @provider.BatchV4StartOptions,
) -> @provider.BatchV4StartResult raise {
  let prepared_requests : Array[Json] = []
  let batch_warnings : Array[@provider.BatchV4RequestWarning] = []
  for request in options.requests {
    match request {
      @provider.BatchImageRequest(_) =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="Anthropic Message Batches image requests",
        )
      @provider.BatchTextRequest(text) => {
        let call_options = self.text_call_options(text)
        let prepared = prepare_anthropic_v4_request(
          text.model_id,
          call_options,
          self.provider_name,
          false,
        )
        prepared_requests.push(
          Json::object(
            Map([
              ("custom_id", Json::string(text.request_id)),
              ("params", prepared.body),
            ]),
          ),
        )
        for warning in prepared.warnings {
          batch_warnings.push({ request_id: Some(text.request_id), warning, })
        }
      }
    }
  }
  let batch = self.post(
    url=self.batches_url(""),
    body={ "requests": Json::array(prepared_requests) },
    @provider.BatchV4OperationOptions::new(
      batch_id="",
      call_options=options.call_options,
    ),
  )
  @provider.BatchV4StartResult::new(
    batch_id=@provider_utils.json_string_field(batch, "id").unwrap_or(""),
    status=anthropic_batch_status(batch),
    warnings=batch_warnings,
  )
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn do_get_batch_status(
  self : AnthropicBatch,
  options : @provider.BatchV4OperationOptions,
) -> @provider.BatchV4Status raise {
  let batch = self.post(
    url=self.batches_url(
      "/\{@provider_utils.encode_path_segment(options.batch_id)}",
    ),
    body=Json::empty_object(),
    options,
  )
  anthropic_batch_status(batch)
}

///|
fn anthropic_batch_result_to_item(
  line : Json,
  provider_name : String,
  id_generator~ : @provider_utils.IdGenerator,
  tool_name_mapping~ : @provider_utils.ToolNameMapping,
) -> @provider.BatchV4ItemResult raise {
  let request_id = @provider_utils.json_string_field(line, "custom_id").unwrap_or(
    "",
  )
  match line {
    { "result": { "type": "succeeded", "message": Object(message), .. }, .. } => {
      let decoded = decode_messages_response_with_metadata(
        Json::object(message),
        provider_name~,
        canonical_metadata=true,
        include_custom_provider_metadata=false,
        mark_code_execution_dynamic=false,
        uses_json_response_tool=false,
        tool_name_mapping~,
        id_generator~,
        citation_documents=[],
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
      @provider.BatchItemSucceeded(
        id=request_id,
        modality=@provider.BatchModalityText,
        result=@provider.BatchTextResult(generate_result),
        provider_metadata=Map([]),
      )
    }
    { "result": { "type": "errored", .. }, .. } =>
      @provider.BatchItemFailed(
        id=request_id,
        modality=@provider.BatchModalityText,
        error=@provider.BatchV4Error::new(
          message="batch request errored",
          error_type="errored",
        ),
        provider_metadata=Map([]),
      )
    { "result": { "type": "canceled", .. }, .. } =>
      @provider.BatchItemTerminated(
        id=request_id,
        modality=@provider.BatchModalityText,
        state=@provider.BatchCancelled,
        error=None,
        provider_metadata=Map([]),
      )
    { "result": { "type": "expired", .. }, .. } =>
      @provider.BatchItemTerminated(
        id=request_id,
        modality=@provider.BatchModalityText,
        state=@provider.BatchExpired,
        error=None,
        provider_metadata=Map([]),
      )
    _ =>
      @provider.BatchItemFailed(
        id=request_id,
        modality=@provider.BatchModalityText,
        error=@provider.BatchV4Error::new(message="batch result was invalid"),
        provider_metadata=Map([]),
      )
  }
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn do_get_batch_results(
  self : AnthropicBatch,
  options : @provider.BatchV4OperationOptions,
) -> Array[@provider.BatchV4ItemResult] raise {
  // Resolve the results URL from the batch status.
  let status = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=self.batches_url(
      "/\{@provider_utils.encode_path_segment(options.batch_id)}",
    ),
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=anthropic_error_message,
    transport=self.http_transport,
  )
  let results_url = @provider_utils.json_string_field(
    status.value,
    "results_url",
  )
  guard results_url is Some(url) else { return [] }
  let content = @provider_utils.get_bytes(
    provider_name=self.provider_name,
    url~,
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
    results.push(
      anthropic_batch_result_to_item(
        json,
        self.provider_name,
        id_generator=self.id_generator,
        tool_name_mapping=@provider_utils.ToolNameMapping::identity(),
      ),
    )
  }
  results
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn do_cancel_batch(
  self : AnthropicBatch,
  options : @provider.BatchV4OperationOptions,
) -> @provider.BatchV4CancelResult raise {
  let json = self.post(
    url=self.batches_url(
      "/\{@provider_utils.encode_path_segment(options.batch_id)}/cancel",
    ),
    body=Json::empty_object(),
    options,
  )
  let details : Map[String, Json] = Map([])
  put_optional_string(
    details,
    key="cancel_initiated_at",
    value=@provider_utils.json_string_field(json, "cancel_initiated_at"),
  )
  @provider.BatchV4CancelResult::new(
    provider_metadata=Map([("anthropic", Json::object(details))]),
  )
}

///|
impl @provider.BatchV4 for AnthropicBatch with fn do_list_batches(
  self : AnthropicBatch,
  options : @provider.BatchV4ListOptions,
) -> @provider.BatchV4ListResult raise {
  let query_params : Map[String, String] = Map([])
  if options.limit is Some(limit) {
    query_params["limit"] = limit.to_string()
  }
  if options.cursor is Some(cursor) {
    query_params["after_id"] = cursor
  }
  let url = @provider_utils.append_query(self.batches_url(""), query_params)
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url~,
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    cancellation_token?=options.call_options.cancellation_token,
    error_to_message=anthropic_error_message,
    transport=self.http_transport,
  )
  let batches : Array[@provider.BatchV4ListItem] = []
  let mut next_cursor : String? = None
  match response.value {
    { "data": Array(items), "has_more": True, .. } => {
      for item in items {
        batches.push({
          batch_id: @provider_utils.json_string_field(item, "id").unwrap_or(""),
          status: anthropic_batch_status(item),
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
          status: anthropic_batch_status(item),
        })
      }
    _ => ()
  }
  @provider.BatchV4ListResult::new(batches~, next_cursor?)
}

///|
/// Select the Message Batches API from an Anthropic provider factory.
pub fn AnthropicProvider::batch(self : AnthropicProvider) -> &@provider.BatchV4 {
  let batch = anthropic_batch(
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    auth_token=self.auth_token,
    api_key_environment_variable=self.api_key_environment_variable,
    anthropic_version=self.anthropic_version,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    id_generator=self.id_generator,
  )
  batch as &@provider.BatchV4
}

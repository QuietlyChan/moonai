///|
/// Open Responses' native implementation of the versioned language-model
/// contract. The wire implementation stays in this package; the public V4
/// contract comes from `provider`.
priv struct OpenResponsesLanguageModelV4 {
  model : OpenResponsesLanguageModel
}

///|
/// Construct a V4 Open Responses model from the provider's concrete model.
fn OpenResponsesLanguageModelV4::new(
  model : OpenResponsesLanguageModel,
) -> OpenResponsesLanguageModelV4 {
  { model, }
}

///|
impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider_name
}

///|
impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id
}

///|
impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::http("image/*")]
}

///|
impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let prepared = prepare_open_responses_v4_request(
    self.model.model_id,
    options,
    self.model.provider_options_name,
    false,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.model.provider_name,
    url=self.model.url,
    headers=@provider_utils.merge_headers(
      self.model.request_headers(),
      options.headers,
    ),
    body=prepared.body,
    timeout_ms=self.model.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=response_error_message,
    transport=self.model.http_transport,
  )
  let protocol_error = match response_error_message(response.value) {
    Some(message) => Some((message, 400))
    None =>
      match missing_responses_output_message(response.value) {
        Some(message) => Some((message, 500))
        None => None
      }
  }
  if protocol_error is Some((message, status_code)) {
    raise @provider.APICallError(
      message~,
      url=self.model.url,
      request_body=response.request.body,
      request_headers=response.request.headers,
      status_code=Some(status_code),
      response_headers=response.response.headers,
      response_body=response.response.body.unwrap_or(response.value.stringify()),
      is_retryable=false,
      data=Some(response.value),
      cause=None,
    )
  }
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_open_responses_response_data(
      value,
      id_generator=self.model.id_generator,
    )
  })
  let response_metadata = @provider.merge_response_metadata(
    decoded.response,
    response.response,
  )
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata: @provider_utils.provider_metadata_from_json(
      response.value,
      self.model.provider_name,
    ),
    request: Some(response.request),
    response: Some(response_metadata),
    warnings: prepared.warnings,
  }
}

///|
impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = prepare_open_responses_v4_request(
    self.model.model_id,
    options,
    self.model.provider_options_name,
    true,
  )
  let decoder = @protocol.OpenResponsesV4StreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.model.provider_name,
    id_generator=self.model.id_generator,
  )
  let warnings = prepared.warnings
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.model.provider_name,
    url=self.model.url,
    headers=@provider_utils.merge_headers(
      self.model.request_headers(),
      options.headers,
    ),
    body=prepared.body,
    idle_timeout_ms=self.model.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=response_error_message,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    finish_stream=() => decoder.finish_stream(),
    response=() => decoder.response_metadata_snapshot(),
    transport=self.model.http_transport,
    on_event~,
  )
  let response_metadata = @provider.merge_response_metadata(
    result.value,
    result.response,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(response_metadata),
  )
}

///|
/// Open Responses' native implementation of the versioned language-model
/// contract. The wire implementation stays in this package; the public V4
/// contract comes from `provider`.
pub struct OpenResponsesLanguageModelV4 {
  model : OpenResponsesLanguageModel
}

///|
/// Construct a V4 Open Responses model from the provider's concrete model.
pub fn OpenResponsesLanguageModelV4::new(
  model : OpenResponsesLanguageModel,
) -> OpenResponsesLanguageModelV4 {
  { model, }
}

///|
pub impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn do_generate(
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
      status_code~,
      response_headers=response.response.headers,
      response_body=response.response.body.unwrap_or(response.value.stringify()),
      is_retryable=false,
    )
  }
  let decoded = decode_open_responses_response_data(
    response.value,
    id_generator=self.model.id_generator,
  )
  let response_metadata = @provider.merge_response_metadata(
    decoded.response_metadata,
    response.response,
  )
  {
    content: decoded.content,
    finish_reason: @provider.LanguageModelV4FinishReason::from_finish_reason(
      decoded.finish_reason,
    ).with_raw(decoded.finish_reason_raw),
    usage: open_responses_v4_usage_from_json(decoded.raw_usage),
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
pub impl @provider.LanguageModelV4 for OpenResponsesLanguageModelV4 with fn do_stream(
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
  let decoder = OpenResponsesStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.model.provider_name,
    id_generator=self.model.id_generator,
  )
  let warnings = prepared.warnings
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse(
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
    warnings~,
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    transport=self.model.http_transport,
    on_event=event => {
      match event {
        @provider.StreamStart =>
          on_event(
            @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
          )
        @provider.Warning(_) => ()
        @provider.Finish(..) =>
          on_event(
            @provider.V4Finish(
              usage=decoder.v4_usage(),
              reason=decoder.v4_finish_reason(),
              provider_metadata=decoder.provider_metadata_snapshot(),
            ),
          )
        other =>
          on_event(
            @provider.LanguageModelV4StreamPart::from_stream_event(other),
          )
      }
    },
  )
  let response_metadata = @provider.merge_response_metadata(
    result.value.response,
    result.response,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(response_metadata),
    usage=decoder.v4_usage(),
    finish_reason=decoder.v4_finish_reason(),
    provider_metadata=decoder.provider_metadata_snapshot(),
    warnings~,
  )
}

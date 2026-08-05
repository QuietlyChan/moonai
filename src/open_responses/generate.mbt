///|
async fn OpenResponsesLanguageModel::generate_responses(
  self : OpenResponsesLanguageModel,
  options : @provider.ChatCallOptions,
) -> @provider.ChatResponse {
  let prepared = prepare_open_responses_request(
    self.model_id,
    options,
    self.provider_options_name,
    false,
  )
  let request_body = prepared.body
  let request_headers = @provider_utils.merge_headers(
    self.request_headers(),
    options.headers,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.url,
    headers=request_headers,
    body=request_body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=response_error_message,
    transport=self.http_transport,
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
      url=self.url,
      request_body=response.request.body,
      request_headers=response.request.headers,
      status_code~,
      response_headers=response.response.headers,
      response_body=response.response.body.unwrap_or(response.value.stringify()),
      is_retryable=false,
    )
  }
  let decoded = decode_responses_response(
    response.value,
    id_generator=self.id_generator,
  )
  let warnings = prepared.warnings
  decoded
  .with_diagnostics(
    None,
    decoded.response,
    @provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    warnings,
  )
  .with_transport(response.request, response.response)
}

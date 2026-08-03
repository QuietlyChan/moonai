///|
async fn OpenResponsesLanguageModel::generate_responses(
  self : OpenResponsesLanguageModel,
  options : @moonai.ChatCallOptions,
) -> @moonai.ChatResponse {
  let request_body = encode_responses_request(
    self.model_id,
    options,
    stream=false,
  )
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
  )
  let decoded = decode_responses_response(response.value)
  let warnings = open_responses_warnings(options)
  decoded
  .with_diagnostics(
    None,
    None,
    @provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    warnings,
  )
  .with_transport(response.request, response.response)
}

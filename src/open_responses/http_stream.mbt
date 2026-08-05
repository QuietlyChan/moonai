///|
async fn OpenResponsesLanguageModel::stream_responses(
  self : OpenResponsesLanguageModel,
  options : @provider.ChatCallOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.ChatResponse {
  let prepared = prepare_open_responses_request(
    self.model_id,
    options,
    self.provider_options_name,
    true,
  )
  let decoder = OpenResponsesStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    id_generator=self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.url,
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=response_error_message,
    warnings~,
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    transport=self.http_transport,
    on_event~,
  )
  result.value
  .with_diagnostics(
    None,
    result.value.response,
    result.value.provider_metadata,
    warnings,
  )
  .with_transport(result.request, result.response)
}

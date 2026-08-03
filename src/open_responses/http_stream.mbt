///|
async fn OpenResponsesLanguageModel::stream_responses(
  self : OpenResponsesLanguageModel,
  options : @moonai.ChatCallOptions,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.ChatResponse {
  let decoder = OpenResponsesStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
  )
  let cancellation_token = options.cancellation_token
  let warnings = open_responses_warnings(options)
  let result = @http_sse.post_json_sse(
    provider_name=self.provider_name,
    url=self.url,
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=encode_responses_request(self.model_id, options),
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    warnings~,
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
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

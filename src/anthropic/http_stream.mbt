///|
async fn AnthropicMessagesModel::stream_messages(
  self : AnthropicMessagesModel,
  options : @moonai.ChatCallOptions,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.ChatResponse {
  let decoder = AnthropicStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
  )
  let cancellation_token = options.cancellation_token
  let warnings = anthropic_warnings(options)
  let result = @http_sse.post_json_sse(
    provider_name=self.provider_name,
    url=self.messages_url(),
    headers=self.request_headers(options),
    body=encode_messages_request(self.model_id, options),
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="message_stop",
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

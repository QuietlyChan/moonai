///|
async fn OpenAICompatibleChatModel::stream_chat(
  self : OpenAICompatibleChatModel,
  options : @moonai.ChatCallOptions,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.ChatResponse {
  let decoder = OpenAICompatibleStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
  )
  let cancellation_token = options.cancellation_token
  let result = @http_sse.post_json_sse(
    provider_name=self.provider_name,
    url=self.chat_completions_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=encode_chat_request(
      self.model_id,
      options,
      preserve_reasoning=self.preserve_reasoning,
      include_usage=self.include_usage,
    ),
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
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
    [],
  )
  .with_transport(result.request, result.response)
}

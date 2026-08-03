///|
async fn OpenAICompatibleChatModel::stream_chat(
  self : OpenAICompatibleChatModel,
  options : @moonai.ChatCallOptions,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.ChatResponse {
  let decoder = OpenAICompatibleStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
  )
  @http_sse.post_json_sse(
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
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    on_event~,
  )
}

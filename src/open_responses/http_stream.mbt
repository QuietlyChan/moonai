///|
async fn OpenResponsesLanguageModel::stream_responses(
  self : OpenResponsesLanguageModel,
  options : @moonai.ChatCallOptions,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.ChatResponse {
  let decoder = OpenResponsesStreamDecoder::new()
  @http_sse.post_json_sse(
    provider_name=self.provider_name,
    url=self.url,
    headers=self.request_headers(),
    body=encode_responses_request(self.model_id, options),
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    on_event~,
  )
}

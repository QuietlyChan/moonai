///|
async fn OpenAICompatibleChatModel::stream_chat(
  self : OpenAICompatibleChatModel,
  options : @provider.ChatCallOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.ChatResponse {
  let prepared = prepare_compatible_chat_request(
    self.model_id,
    options,
    self.preserve_reasoning,
    self.include_usage,
    true,
    self.provider_name,
    self.supports_structured_outputs,
    self.supports_top_k,
    self.supports_frequency_penalty,
    self.prompt_converter,
  )
  let metadata_extractor = self.metadata_extractor
  let decoder = OpenAICompatibleStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    metadata_key=prepared.metadata_key,
    error_structure=self.error_structure,
    metadata_extractor?,
    convert_usage=self.convert_usage,
    id_generator=self.id_generator,
    generate_reasoning_ids=self.generate_reasoning_ids,
  )
  let cancellation_token = options.cancellation_token
  let warnings = prepared.warnings
  let request_body = (self.transform_request_body)(prepared.body)
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.chat_completions_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=request_body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=json => self.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.error_structure.retryable(status_code, error)
    },
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

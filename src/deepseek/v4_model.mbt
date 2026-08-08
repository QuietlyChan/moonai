///|
impl @provider.LanguageModelV4 for DeepSeekChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for DeepSeekChatLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
impl @provider.LanguageModelV4 for DeepSeekChatLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
impl @provider.LanguageModelV4 for DeepSeekChatLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for DeepSeekChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let prepared = prepare_deepseek_v4_request(
    self.model_id,
    options,
    self.provider_name,
    false,
    self.supports_thinking,
    self.supports_structured_outputs,
  )
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.chat_url(),
    headers=self.request_headers(options.headers),
    body=prepared.body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=deepseek_error_message,
    validate_response=validate_deepseek_chat_response,
    transport=self.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_deepseek_chat_response(
      value,
      provider_name=self.provider_name,
      id_generator=self.id_generator,
    )
  })
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata: decoded.provider_metadata,
    request: Some(response.request),
    response: Some(
      @provider.merge_response_metadata(decoded.response, response.response),
    ),
    warnings: prepared.warnings,
  }
}

///|
impl @provider.LanguageModelV4 for DeepSeekChatLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = prepare_deepseek_v4_request(
    self.model_id,
    options,
    self.provider_name,
    true,
    self.supports_thinking,
    self.supports_structured_outputs,
  )
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    id_generator=self.id_generator,
  )
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=self.chat_url(),
    headers=self.request_headers(options.headers),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=deepseek_error_message,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    finish_stream=() => decoder.finish_stream(),
    response=() => decoder.response_metadata_snapshot(),
    transport=self.http_transport,
    on_event~,
  )
  let response_metadata = @provider.merge_response_metadata(
    result.value,
    result.response,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(response_metadata),
  )
}

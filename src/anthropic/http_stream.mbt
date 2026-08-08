///|
async fn AnthropicLanguageModel::stream_v4(
  self : AnthropicLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
  on_event : async (@provider.LanguageModelV4StreamPart) -> Unit,
) -> @provider.LanguageModelV4StreamResult {
  let citation_documents = extract_anthropic_citation_documents(
    options.prompt,
    self.provider_name,
  )
  let prepared = self.prepare_v4_request(options, true)
  let decoder = AnthropicV4StreamDecoder::new(
    emit_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    canonical_metadata=true,
    include_custom_provider_metadata=prepared.used_custom_provider_key,
    mark_code_execution_dynamic=prepared.mark_code_execution_dynamic,
    uses_json_response_tool=prepared.uses_json_response_tool,
    tool_name_mapping=prepared.tool_name_mapping,
    id_generator=self.id_generator,
    citation_documents~,
  )
  let cancellation_token = options.cancellation_token
  let warnings = prepared.warnings
  let request_body = self.apply_request_body_transform(
    prepared.body,
    prepared.beta_features,
    options.headers,
  )
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=self.messages_url(true),
    headers=self.request_headers(
      options.headers,
      request_beta_features=prepared.beta_features,
    ),
    body=request_body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="message_stop",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=anthropic_error_message,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response_metadata_snapshot(),
    transport=self.http_transport,
    on_event~,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(@provider.merge_response_metadata(result.value, result.response)),
  )
}

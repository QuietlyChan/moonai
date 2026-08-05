///|
async fn AnthropicMessagesModel::stream_v4(
  self : AnthropicMessagesModel,
  options : @provider.LanguageModelV4CallOptions,
  on_event : async (@provider.LanguageModelV4StreamPart) -> Unit,
) -> @provider.LanguageModelV4StreamResult {
  let prepared = prepare_anthropic_v4_request(
    self.model_id,
    options,
    self.provider_name,
    true,
  )
  let decoder = AnthropicStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    tool_name_mapping=prepared.tool_name_mapping,
    id_generator=self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.messages_url(),
    headers=self.request_headers(
      options.headers,
      request_beta_features=prepared.beta_features,
    ),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="message_stop",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=anthropic_error_message,
    warnings~,
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    transport=self.http_transport,
    on_event=event => {
      match event {
        @provider.StreamStart =>
          on_event(
            @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
          )
        @provider.Warning(_) => ()
        @provider.Finish(..) =>
          on_event(
            @provider.V4Finish(
              usage=decoder.v4_usage(),
              reason=decoder.v4_finish_reason(),
              provider_metadata=decoder.provider_metadata_snapshot(),
            ),
          )
        other =>
          on_event(
            @provider.LanguageModelV4StreamPart::from_stream_event(other),
          )
      }
    },
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(
      @provider.merge_response_metadata(result.value.response, result.response),
    ),
    usage=decoder.v4_usage(),
    finish_reason=decoder.v4_finish_reason(),
    provider_metadata=decoder.provider_metadata_snapshot(),
    warnings~,
  )
}

///|
async fn AnthropicMessagesModel::stream_messages(
  self : AnthropicMessagesModel,
  options : @provider.ChatCallOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.ChatResponse {
  let prepared = prepare_anthropic_request(
    self.model_id,
    options,
    self.provider_name,
    true,
  )
  let decoder = AnthropicStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    tool_name_mapping=prepared.tool_name_mapping,
    id_generator=self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.messages_url(),
    headers=self.request_headers(
      options.headers,
      request_beta_features=prepared.beta_features,
    ),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="message_stop",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=anthropic_error_message,
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

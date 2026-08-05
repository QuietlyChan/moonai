///|
async fn AnthropicMessagesModel::generate_v4(
  self : AnthropicMessagesModel,
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4GenerateResult {
  let prepared = prepare_anthropic_v4_request(
    self.model_id,
    options,
    self.provider_name,
    false,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.messages_url(),
    headers=self.request_headers(
      options.headers,
      request_beta_features=prepared.beta_features,
    ),
    body=prepared.body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=anthropic_error_message,
    transport=self.http_transport,
  )
  let decoded = decode_messages_response(
    response.value,
    provider_name=self.provider_name,
    tool_name_mapping=prepared.tool_name_mapping,
    id_generator=self.id_generator,
  )
  let raw_usage = anthropic_response_usage_json(response.value)
  let raw_finish_reason = anthropic_response_stop_reason(response.value)
  {
    content: decoded.content.copy(),
    finish_reason: anthropic_v4_finish_reason(
      decoded.finish_reason,
      raw_finish_reason,
    ),
    usage: anthropic_v4_usage_from_raw(raw_usage),
    provider_metadata: @provider.merge_provider_metadata(
      decoded.provider_metadata,
      @provider_utils.provider_metadata_from_json(
        response.value,
        self.provider_name,
      ),
    ),
    request: Some(response.request),
    response: Some(
      @provider.merge_response_metadata(decoded.response, response.response),
    ),
    warnings: prepared.warnings,
  }
}

///|
async fn AnthropicMessagesModel::generate_messages(
  self : AnthropicMessagesModel,
  options : @provider.ChatCallOptions,
) -> @provider.ChatResponse {
  self.generate_v4(anthropic_v4_options_from_chat(options)).to_chat_response()
}

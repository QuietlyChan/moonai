///|
fn AnthropicLanguageModel::prepare_v4_request(
  self : AnthropicLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
  stream : Bool,
) -> AnthropicPreparedRequest raise {
  if self.supports_native_structured_output && self.supports_strict_tools {
    prepare_anthropic_v4_request(
      self.model_id,
      options,
      self.provider_name,
      stream,
    )
  } else {
    prepare_anthropic_v4_request_with_config(
      self.model_id,
      options,
      self.provider_name,
      stream,
      self.supports_native_structured_output,
      self.supports_strict_tools,
    )
  }
}

///|
async fn AnthropicLanguageModel::generate_v4(
  self : AnthropicLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4GenerateResult {
  let citation_documents = extract_anthropic_citation_documents(
    options.prompt,
    self.provider_name,
  )
  let prepared = self.prepare_v4_request(options, false)
  let cancellation_token = options.cancellation_token
  let request_body = self.apply_request_body_transform(
    prepared.body,
    prepared.beta_features,
    options.headers,
  )
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.messages_url(false),
    headers=self.request_headers(
      options.headers,
      request_beta_features=prepared.beta_features,
    ),
    body=request_body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=anthropic_error_message,
    validate_response=validate_anthropic_messages_response,
    transport=self.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_messages_response_with_metadata(
      value,
      provider_name=self.provider_name,
      canonical_metadata=true,
      include_custom_provider_metadata=prepared.used_custom_provider_key,
      mark_code_execution_dynamic=prepared.mark_code_execution_dynamic,
      uses_json_response_tool=prepared.uses_json_response_tool,
      tool_name_mapping=prepared.tool_name_mapping,
      id_generator=self.id_generator,
      citation_documents~,
    )
  })
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
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

///|
async fn OpenAICompatibleChatModel::generate_chat(
  self : OpenAICompatibleChatModel,
  options : @provider.ChatCallOptions,
) -> @provider.ChatResponse {
  let effective_options = (self.transform_chat_options)(options)
  let prepared = prepare_compatible_chat_request(
    self.model_id,
    effective_options,
    self.preserve_reasoning,
    self.include_usage,
    false,
    self.provider_name,
    self.supports_structured_outputs,
    self.supports_top_k,
    self.supports_frequency_penalty,
    self.prompt_converter,
  )
  let request_body = (self.transform_request_body)(prepared.body)
  let warnings = prepared.warnings
  let request_headers = @provider_utils.merge_headers(
    self.request_headers(),
    effective_options.headers,
  )
  let cancellation_token = effective_options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.chat_completions_url(),
    headers=request_headers,
    body=request_body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=effective_options.retry_policy,
    cancellation_token?,
    error_to_message=json => self.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.error_structure.retryable(status_code, error)
    },
    transport=self.http_transport,
  )
  let decoded = decode_chat_response(
    response.value,
    error_structure=self.error_structure,
    convert_usage=self.convert_usage,
    metadata_key=prepared.metadata_key,
    id_generator=self.id_generator,
  )
  let provider_metadata = @provider.merge_provider_metadata(
    @provider.merge_provider_metadata(
      @provider_utils.provider_metadata_from_json(
        response.value,
        self.provider_name,
      ),
      match self.metadata_extractor {
        Some(extractor) => extractor.extract_metadata(response.value)
        None => Map([])
      },
    ),
    decoded.provider_metadata,
  )
  decoded
  .with_diagnostics(None, decoded.response, provider_metadata, warnings)
  .with_transport(response.request, response.response)
}

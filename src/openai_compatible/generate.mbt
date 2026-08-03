///|
async fn OpenAICompatibleChatModel::generate_chat(
  self : OpenAICompatibleChatModel,
  options : @moonai.ChatCallOptions,
) -> @moonai.ChatResponse {
  let request_body = encode_chat_request(
    self.model_id,
    options,
    preserve_reasoning=self.preserve_reasoning,
    include_usage=self.include_usage,
    stream=false,
  )
  let request_headers = @provider_utils.merge_headers(
    self.request_headers(),
    options.headers,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.chat_completions_url(),
    headers=request_headers,
    body=request_body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
  )
  let decoded = decode_chat_response(response.value)
  decoded
  .with_diagnostics(
    None,
    None,
    @provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    [],
  )
  .with_transport(response.request, response.response)
}

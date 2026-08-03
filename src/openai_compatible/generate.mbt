///|
async fn OpenAICompatibleChatModel::generate_chat(
  self : OpenAICompatibleChatModel,
  options : @moonai.ChatCallOptions,
) -> @moonai.ChatResponse {
  let response = @provider_utils.post_json(
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
      stream=false,
    ),
    timeout_ms=self.idle_timeout_ms,
  )
  decode_chat_response(response)
}

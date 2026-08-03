///|
async fn OpenResponsesLanguageModel::generate_responses(
  self : OpenResponsesLanguageModel,
  options : @moonai.ChatCallOptions,
) -> @moonai.ChatResponse {
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.url,
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=encode_responses_request(self.model_id, options, stream=false),
    timeout_ms=self.idle_timeout_ms,
  )
  decode_responses_response(response)
}

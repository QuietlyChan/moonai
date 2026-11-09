///|
/// Perplexity Agent API language model with search-grounded responses.
struct PerplexityLanguageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int32
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
}

///|
fn perplexity_chat_value(
  model_id : PerplexityLanguageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int32,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> PerplexityLanguageModel {
  {
    provider_name: "perplexity",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    id_generator,
    http_transport,
  }
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn provider(
  _self,
) -> String {
  "perplexity"
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::http("image/*")]
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn do_generate(
  self,
  options,
) {
  let prepared = self.prepare_agent_request(options)
  let url = @provider_utils.append_path(self.base_url, "/v1/agent")
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url~,
    headers=perplexity_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=prepared.body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=perplexity_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let value = response.value
  match value {
    { "status": "failed", .. } | { "error": Object(_), .. } =>
      raise @provider.APICallError(
        message=match value {
          { "error": { "message": String(message), .. }, .. } => message
          _ => "Perplexity response failed"
        },
        url~,
        request_body=prepared.body.stringify(),
        request_headers=@provider_utils.copy_headers(options.headers),
        status_code=response.response.status_code,
        response_headers=@provider_utils.copy_headers(response.response.headers),
        response_body=value.stringify(),
        is_retryable=false,
        data=Some(value),
        cause=None,
      )
    _ => ()
  }
  let decoded = @provider_utils.handle_json_response(response, value => {
    perplexity_agent_decoded_response(value, self.id_generator)
  })
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata: decoded.provider_metadata,
    request: Some(response.request),
    response: Some({
      ..@provider.merge_response_metadata(decoded.response, response.response),
      body: Some(value.stringify()),
    }),
    warnings: prepared.warnings,
  }
}

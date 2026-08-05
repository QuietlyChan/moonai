///|
/// Official OpenAI Chat Completions model.
pub struct OpenAIChatModel {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv model_id : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn OpenAIChatModel::chat_completions_url(self : OpenAIChatModel) -> String {
  @provider_utils.append_path(self.base_url, "/chat/completions")
}

///|
fn OpenAIChatModel::request_headers(
  self : OpenAIChatModel,
  options : @provider.ChatCallOptions,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/openai/\{VERSION}"],
    ),
    options.headers,
  )
}

///|
async fn OpenAIChatModel::generate_chat(
  self : OpenAIChatModel,
  options : @provider.ChatCallOptions,
) -> @provider.ChatResponse {
  let prepared = prepare_openai_chat_request(
    self.model_id,
    options,
    self.provider_name,
    false,
    self.preserve_reasoning,
    self.include_usage,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.chat_completions_url(),
    headers=self.request_headers(options),
    body=prepared.body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let decoded = decode_openai_chat_response(
    response.value,
    self.provider_name,
    self.id_generator,
  )
  decoded
  .with_diagnostics(
    None,
    decoded.response,
    decoded.provider_metadata,
    prepared.warnings,
  )
  .with_transport(response.request, response.response)
}

///|
async fn OpenAIChatModel::stream_chat(
  self : OpenAIChatModel,
  options : @provider.ChatCallOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.ChatResponse {
  let prepared = prepare_openai_chat_request(
    self.model_id,
    options,
    self.provider_name,
    true,
    self.preserve_reasoning,
    self.include_usage,
  )
  let decoder = OpenAIChatStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    id_generator=self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.chat_completions_url(),
    headers=self.request_headers(options),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    warnings=prepared.warnings,
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
    prepared.warnings,
  )
  .with_transport(result.request, result.response)
}

///|
pub impl @provider.ChatModel for OpenAIChatModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ChatModel for OpenAIChatModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ChatModel for OpenAIChatModel with fn supported_urls(_self) -> Array[
  @provider.SupportedUrlRule,
] {
  [@provider.SupportedUrlRule::http("image/*")]
}

///|
pub impl @provider.ChatModel for OpenAIChatModel with fn generate(self, options) {
  self.generate_chat(options)
}

///|
pub impl @provider.ChatModel for OpenAIChatModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_chat(options, on_event)
}

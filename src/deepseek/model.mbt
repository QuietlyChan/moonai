///|
/// DeepSeek provider factory.
pub struct DeepSeekProvider {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv supports_thinking : Bool
  priv supports_structured_outputs : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// DeepSeek Chat Completions model.
pub struct DeepSeekChatModel {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv supports_thinking : Bool
  priv supports_structured_outputs : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn load_deepseek_api_key(
  api_key : String,
) -> String raise @provider.LoadAPIKeyError {
  @provider_utils.load_api_key(
    api_key,
    environment_variable_name="DEEPSEEK_API_KEY",
    description="DeepSeek",
  )
}

///|
/// Create a DeepSeek provider.
pub fn create_deepseek(
  api_key? : String = "",
  base_url? : String = "https://api.deepseek.com",
  provider_name? : String = "deepseek",
  headers? : Map[String, String] = Map([]),
  supports_thinking? : Bool = true,
  supports_structured_outputs? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> DeepSeekProvider {
  {
    provider_name,
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    supports_thinking,
    supports_structured_outputs,
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createDeepSeek(
  api_key? : String = "",
  base_url? : String = "https://api.deepseek.com",
  provider_name? : String = "deepseek",
  headers? : Map[String, String] = Map([]),
  supports_thinking? : Bool = true,
  supports_structured_outputs? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> DeepSeekProvider {
  create_deepseek(
    api_key~,
    base_url~,
    provider_name~,
    headers~,
    supports_thinking~,
    supports_structured_outputs~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select the protocol-level DeepSeek chat model.
pub fn DeepSeekProvider::chat_wire(
  self : DeepSeekProvider,
  model_id : DeepSeekChatModelId,
) -> DeepSeekChatModel {
  {
    provider_name: self.provider_name + ".chat",
    api_key: self.api_key,
    base_url: self.base_url,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    supports_thinking: self.supports_thinking,
    supports_structured_outputs: self.supports_structured_outputs,
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    http_transport: self.http_transport,
  }
}

///|
/// Select a DeepSeek chat language model.
pub fn DeepSeekProvider::chat(
  self : DeepSeekProvider,
  model_id : DeepSeekChatModelId,
) -> DeepSeekLanguageModelV4 {
  DeepSeekLanguageModelV4::new(self.chat_wire(model_id))
}

///|
/// Select the default DeepSeek language model.
pub fn DeepSeekProvider::language_model(
  self : DeepSeekProvider,
  model_id : DeepSeekChatModelId,
) -> DeepSeekLanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn DeepSeekProvider::languageModel(
  self : DeepSeekProvider,
  model_id : DeepSeekChatModelId,
) -> DeepSeekLanguageModelV4 {
  self.language_model(model_id)
}

///|
fn DeepSeekChatModel::request_headers(
  self : DeepSeekChatModel,
  options : @provider.ChatCallOptions,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer " + load_deepseek_api_key(self.api_key)
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/deepseek/\{VERSION}"],
    ),
    options.headers,
  )
}

///|
fn DeepSeekChatModel::chat_url(self : DeepSeekChatModel) -> String {
  @provider_utils.append_path(self.base_url, "/chat/completions")
}

///|
async fn DeepSeekChatModel::generate_chat(
  self : DeepSeekChatModel,
  options : @provider.ChatCallOptions,
) -> @provider.ChatResponse {
  let prepared = prepare_deepseek_request(
    self.model_id,
    options,
    self.provider_name,
    false,
    self.supports_thinking,
    self.supports_structured_outputs,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.chat_url(),
    headers=self.request_headers(options),
    body=prepared.body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=deepseek_error_message,
    transport=self.http_transport,
  )
  let decoded = decode_deepseek_chat_response(
    response.value,
    provider_name=self.provider_name,
    id_generator=self.id_generator,
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
async fn DeepSeekChatModel::stream_chat(
  self : DeepSeekChatModel,
  options : @provider.ChatCallOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.ChatResponse {
  let prepared = prepare_deepseek_request(
    self.model_id,
    options,
    self.provider_name,
    true,
    self.supports_thinking,
    self.supports_structured_outputs,
  )
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    id_generator=self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.chat_url(),
    headers=self.request_headers(options),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=deepseek_error_message,
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
pub impl @provider.ChatModel for DeepSeekChatModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ChatModel for DeepSeekChatModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ChatModel for DeepSeekChatModel with fn supported_urls(_self) -> Array[
  @provider.SupportedUrlRule,
] {
  []
}

///|
pub impl @provider.ChatModel for DeepSeekChatModel with fn generate(
  self,
  options,
) {
  self.generate_chat(options)
}

///|
pub impl @provider.ChatModel for DeepSeekChatModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_chat(options, on_event)
}

///|
/// Construct the low-level DeepSeek Chat Completions wire model directly.
pub fn deepseek_chat(
  model_id : DeepSeekChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.deepseek.com",
  headers? : Map[String, String] = Map([]),
  supports_thinking? : Bool = true,
  supports_structured_outputs? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> DeepSeekChatModel {
  create_deepseek(
    api_key~,
    base_url~,
    headers~,
    supports_thinking~,
    supports_structured_outputs~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).chat_wire(model_id)
}

///|
/// Construct the default V4 DeepSeek language model directly.
pub fn deepseek(
  model_id : DeepSeekChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.deepseek.com",
  headers? : Map[String, String] = Map([]),
  supports_thinking? : Bool = true,
  supports_structured_outputs? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> DeepSeekLanguageModelV4 {
  DeepSeekLanguageModelV4::new(
    deepseek_chat(
      model_id,
      api_key~,
      base_url~,
      headers~,
      supports_thinking~,
      supports_structured_outputs~,
      idle_timeout_ms~,
      http_transport?,
      id_generator?,
    ),
  )
}

///|
/// Camel-case direct model factory matching AI SDK naming.
pub fn deepSeek(
  model_id : DeepSeekChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.deepseek.com",
  headers? : Map[String, String] = Map([]),
  supports_thinking? : Bool = true,
  supports_structured_outputs? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> DeepSeekLanguageModelV4 {
  deepseek(
    model_id,
    api_key~,
    base_url~,
    headers~,
    supports_thinking~,
    supports_structured_outputs~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

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
/// DeepSeek Chat Completions model behind the public V4 boundary.
priv struct DeepSeekChatLanguageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  supports_thinking : Bool
  supports_structured_outputs : Bool
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
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
/// Construct the concrete chat model behind the public V4 boundary.
fn DeepSeekProvider::language_model_value(
  self : DeepSeekProvider,
  model_id : DeepSeekChatModelId,
) -> DeepSeekChatLanguageModel {
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
) -> &@provider.LanguageModelV4 {
  let model = self.language_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// Select the default DeepSeek language model.
pub fn DeepSeekProvider::language_model(
  self : DeepSeekProvider,
  model_id : DeepSeekChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn DeepSeekProvider::languageModel(
  self : DeepSeekProvider,
  model_id : DeepSeekChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
fn DeepSeekChatLanguageModel::request_headers(
  self : DeepSeekChatLanguageModel,
  extra_headers : Map[String, String],
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
    extra_headers,
  )
}

///|
fn DeepSeekChatLanguageModel::chat_url(
  self : DeepSeekChatLanguageModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/chat/completions")
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
) -> &@provider.LanguageModelV4 {
  create_deepseek(
    api_key~,
    base_url~,
    headers~,
    supports_thinking~,
    supports_structured_outputs~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
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
) -> &@provider.LanguageModelV4 {
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

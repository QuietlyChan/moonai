///|
/// Moonshot AI provider factory.
pub struct MoonshotAIProvider {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Load the Moonshot API key or fall back to MOONSHOT_API_KEY.
fn load_moonshot_api_key(
  api_key : String,
) -> String raise @provider.LoadAPIKeyError {
  @provider_utils.load_api_key(
    api_key,
    environment_variable_name="MOONSHOT_API_KEY",
    description="Moonshot",
  )
}

///|
/// Create a Moonshot AI provider.
pub fn create_moonshot_ai(
  api_key? : String = "",
  base_url? : String = "https://api.moonshot.ai/v1",
  provider_name? : String = "moonshotai.chat",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MoonshotAIProvider {
  {
    provider_name,
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// AI SDK-style provider factory.
pub fn createMoonshotAI(
  api_key? : String = "",
  base_url? : String = "https://api.moonshot.ai/v1",
  provider_name? : String = "moonshotai.chat",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MoonshotAIProvider {
  create_moonshot_ai(
    api_key~,
    base_url~,
    provider_name~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
fn MoonshotAIProvider::language_model_value(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> MoonshotAIChatLanguageModel {
  MoonshotAIChatLanguageModel::new(
    model_id~,
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    headers=self.headers,
    include_usage=true,
    supports_structured_outputs=get_model_structured_output_support(model_id),
    idle_timeout_ms=self.idle_timeout_ms,
    id_generator=self.id_generator,
    http_transport=self.http_transport,
  )
}

///|
/// Select a Moonshot AI language model.
pub fn MoonshotAIProvider::language_model(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.language_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// AI SDK-style language-model selector.
pub fn MoonshotAIProvider::languageModel(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Select a Moonshot AI chat model.
pub fn MoonshotAIProvider::chat_model(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// AI SDK-style chat-model selector.
pub fn MoonshotAIProvider::chatModel(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat_model(model_id)
}

///|
/// Short chat selector.
pub fn MoonshotAIProvider::chat(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat_model(model_id)
}

///|
/// Construct a default Moonshot AI language model directly.
pub fn moonshotai(
  model_id : MoonshotAIChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.moonshot.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_moonshot_ai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

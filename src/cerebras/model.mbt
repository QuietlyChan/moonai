///|
/// Cerebras provider settings.
pub struct CerebrasProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Cerebras provider. The API key defaults to the
/// `CEREBRAS_API_KEY` environment variable.
pub fn create_cerebras(
  api_key? : String = "",
  base_url? : String = "https://api.cerebras.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> CerebrasProvider {
  {
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
/// Camel-case provider factory matching AI SDK naming.
pub fn createCerebras(
  api_key? : String = "",
  base_url? : String = "https://api.cerebras.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> CerebrasProvider {
  create_cerebras(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a Cerebras chat model.
pub fn CerebrasProvider::chat(
  self : CerebrasProvider,
  model_id : CerebrasChatModelId,
) -> &@provider.LanguageModelV4 {
  cerebras_chat_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    id_generator=self.id_generator,
  )
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn CerebrasProvider::language_model(
  self : CerebrasProvider,
  model_id : CerebrasChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn CerebrasProvider::languageModel(
  self : CerebrasProvider,
  model_id : CerebrasChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn CerebrasProvider::chatModel(
  self : CerebrasProvider,
  model_id : CerebrasChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn language_model(
  self,
  model_id,
) {
  CerebrasProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for CerebrasProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Cerebras language model directly.
pub fn cerebras(
  model_id : CerebrasChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.cerebras.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_cerebras(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

///|
/// Z.AI provider settings.
pub struct ZaiProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Z.AI provider. The API key defaults to the `ZAI_API_KEY`
/// environment variable.
pub fn create_zai(
  api_key? : String = "",
  base_url? : String = "https://api.z.ai/api/paas/v4",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> ZaiProvider {
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
pub fn createZai(
  api_key? : String = "",
  base_url? : String = "https://api.z.ai/api/paas/v4",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> ZaiProvider {
  create_zai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Construct the concrete chat model behind the public V4 boundary.
fn ZaiProvider::language_model_value(
  self : ZaiProvider,
  model_id : ZaiChatModelId,
) -> ZaiChatLanguageModel {
  zai_chat_value(
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
/// Select a Z.AI chat model.
pub fn ZaiProvider::chat(
  self : ZaiProvider,
  model_id : ZaiChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.language_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn ZaiProvider::language_model(
  self : ZaiProvider,
  model_id : ZaiChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn ZaiProvider::languageModel(
  self : ZaiProvider,
  model_id : ZaiChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn ZaiProvider::chatModel(
  self : ZaiProvider,
  model_id : ZaiChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn language_model(
  self,
  model_id,
) {
  ZaiProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for ZaiProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Z.AI language model directly.
pub fn zai(
  model_id : ZaiChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.z.ai/api/paas/v4",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_zai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

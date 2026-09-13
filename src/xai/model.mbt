///|
/// xAI provider settings.
pub struct XaiProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create an xAI provider. The API key defaults to the `XAI_API_KEY`
/// environment variable.
pub fn create_xai(
  api_key? : String = "",
  base_url? : String = "https://api.x.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> XaiProvider {
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
pub fn createXai(
  api_key? : String = "",
  base_url? : String = "https://api.x.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> XaiProvider {
  create_xai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select an xAI chat model.
pub fn XaiProvider::chat(
  self : XaiProvider,
  model_id : XaiChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = xai_chat_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    id_generator=self.id_generator,
  )
  model as &@provider.LanguageModelV4
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn XaiProvider::language_model(
  self : XaiProvider,
  model_id : XaiChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn XaiProvider::languageModel(
  self : XaiProvider,
  model_id : XaiChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn XaiProvider::chatModel(
  self : XaiProvider,
  model_id : XaiChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select an xAI image model.
pub fn XaiProvider::image(
  self : XaiProvider,
  model_id : XaiImageModelId,
) -> &@provider.ImageModelV4 {
  let model = xai_image_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.ImageModelV4
}

///|
/// Alias for `image`.
pub fn XaiProvider::image_model(
  self : XaiProvider,
  model_id : XaiImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
/// Camel-case alias for `image_model`.
pub fn XaiProvider::imageModel(
  self : XaiProvider,
  model_id : XaiImageModelId,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn language_model(
  self,
  model_id,
) {
  XaiProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn image_model(
  self,
  model_id,
) {
  XaiProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for XaiProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 xAI language model directly.
pub fn xai(
  model_id : XaiChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.x.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_xai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

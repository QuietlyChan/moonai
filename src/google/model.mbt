///|
/// Google Gemini provider settings.
pub struct GoogleProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Google Gemini provider. The API key defaults to the
/// `GOOGLE_GENERATIVE_AI_API_KEY` environment variable.
pub fn create_google(
  api_key? : String = "",
  base_url? : String = "https://generativelanguage.googleapis.com/v1beta",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> GoogleProvider {
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
pub fn createGoogle(
  api_key? : String = "",
  base_url? : String = "https://generativelanguage.googleapis.com/v1beta",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> GoogleProvider {
  create_google(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a Google Gemini chat model.
pub fn GoogleProvider::chat(
  self : GoogleProvider,
  model_id : GoogleChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = google_chat_value(
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
pub fn GoogleProvider::language_model(
  self : GoogleProvider,
  model_id : GoogleChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn GoogleProvider::languageModel(
  self : GoogleProvider,
  model_id : GoogleChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn GoogleProvider::chatModel(
  self : GoogleProvider,
  model_id : GoogleChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select a Google embedding model.
pub fn GoogleProvider::embedding(
  self : GoogleProvider,
  model_id : GoogleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = google_embedding_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.EmbeddingModelV4
}

///|
/// Alias for `embedding`.
pub fn GoogleProvider::embedding_model(
  self : GoogleProvider,
  model_id : GoogleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn GoogleProvider::embeddingModel(
  self : GoogleProvider,
  model_id : GoogleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn language_model(
  self,
  model_id,
) {
  GoogleProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn embedding_model(
  self,
  model_id,
) {
  GoogleProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for GoogleProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Google language model directly.
pub fn google(
  model_id : GoogleChatModelId,
  api_key? : String = "",
  base_url? : String = "https://generativelanguage.googleapis.com/v1beta",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_google(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

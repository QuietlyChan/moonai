///|
/// Perplexity provider settings.
pub struct PerplexityProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Perplexity provider. The API key defaults to the
/// `PERPLEXITY_API_KEY` environment variable.
pub fn create_perplexity(
  api_key? : String = "",
  base_url? : String = "https://api.perplexity.ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> PerplexityProvider {
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
pub fn createPerplexity(
  api_key? : String = "",
  base_url? : String = "https://api.perplexity.ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> PerplexityProvider {
  create_perplexity(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a Perplexity chat model.
pub fn PerplexityProvider::chat(
  self : PerplexityProvider,
  model_id : PerplexityLanguageModelId,
) -> &@provider.LanguageModelV4 {
  let model = perplexity_chat_value(
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
pub fn PerplexityProvider::language_model(
  self : PerplexityProvider,
  model_id : PerplexityLanguageModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn PerplexityProvider::languageModel(
  self : PerplexityProvider,
  model_id : PerplexityLanguageModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Select a Perplexity embedding model.
pub fn PerplexityProvider::embedding(
  self : PerplexityProvider,
  model_id : PerplexityEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = perplexity_embedding_value(
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
pub fn PerplexityProvider::embedding_model(
  self : PerplexityProvider,
  model_id : PerplexityEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn PerplexityProvider::embeddingModel(
  self : PerplexityProvider,
  model_id : PerplexityEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn language_model(
  self,
  model_id,
) {
  PerplexityProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn embedding_model(
  self,
  model_id,
) {
  PerplexityProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for PerplexityProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Perplexity language model directly.
pub fn perplexity(
  model_id : PerplexityLanguageModelId,
  api_key? : String = "",
  base_url? : String = "https://api.perplexity.ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_perplexity(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

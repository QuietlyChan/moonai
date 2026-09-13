///|
/// Cohere provider settings.
pub struct CohereProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Cohere provider. The API key defaults to the `COHERE_API_KEY`
/// environment variable.
pub fn create_cohere(
  api_key? : String = "",
  base_url? : String = "https://api.cohere.com/v2",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> CohereProvider {
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
pub fn createCohere(
  api_key? : String = "",
  base_url? : String = "https://api.cohere.com/v2",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> CohereProvider {
  create_cohere(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a Cohere chat model.
pub fn CohereProvider::chat(
  self : CohereProvider,
  model_id : CohereChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = cohere_chat_value(
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
pub fn CohereProvider::language_model(
  self : CohereProvider,
  model_id : CohereChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn CohereProvider::languageModel(
  self : CohereProvider,
  model_id : CohereChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Select a Cohere embedding model.
pub fn CohereProvider::embedding(
  self : CohereProvider,
  model_id : CohereEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = cohere_embedding_value(
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
pub fn CohereProvider::embedding_model(
  self : CohereProvider,
  model_id : CohereEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn CohereProvider::embeddingModel(
  self : CohereProvider,
  model_id : CohereEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Select a Cohere reranking model.
pub fn CohereProvider::reranking(
  self : CohereProvider,
  model_id : CohereRerankingModelId,
) -> &@provider.RerankingModelV4 {
  let model = cohere_reranking_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.RerankingModelV4
}

///|
/// Alias for `reranking`.
pub fn CohereProvider::reranking_model(
  self : CohereProvider,
  model_id : CohereRerankingModelId,
) -> &@provider.RerankingModelV4 {
  self.reranking(model_id)
}

///|
/// Camel-case alias for `reranking_model`.
pub fn CohereProvider::rerankingModel(
  self : CohereProvider,
  model_id : CohereRerankingModelId,
) -> &@provider.RerankingModelV4 {
  self.reranking_model(model_id)
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn language_model(
  self,
  model_id,
) {
  CohereProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn embedding_model(
  self,
  model_id,
) {
  CohereProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn reranking_model(
  self,
  model_id,
) {
  Some(CohereProvider::reranking(self, model_id))
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for CohereProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Cohere language model directly.
pub fn cohere(
  model_id : CohereChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.cohere.com/v2",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_cohere(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

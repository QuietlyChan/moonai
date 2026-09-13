///|
/// Mistral provider settings.
pub struct MistralProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Mistral provider. The API key defaults to the `MISTRAL_API_KEY`
/// environment variable.
pub fn create_mistral(
  api_key? : String = "",
  base_url? : String = "https://api.mistral.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MistralProvider {
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
pub fn createMistral(
  api_key? : String = "",
  base_url? : String = "https://api.mistral.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MistralProvider {
  create_mistral(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a Mistral chat model.
pub fn MistralProvider::chat(
  self : MistralProvider,
  model_id : MistralChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = mistral_chat_value(
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
pub fn MistralProvider::language_model(
  self : MistralProvider,
  model_id : MistralChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn MistralProvider::languageModel(
  self : MistralProvider,
  model_id : MistralChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn MistralProvider::chatModel(
  self : MistralProvider,
  model_id : MistralChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select a Mistral embedding model.
pub fn MistralProvider::embedding(
  self : MistralProvider,
  model_id : MistralEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = mistral_embedding_value(
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
pub fn MistralProvider::embedding_model(
  self : MistralProvider,
  model_id : MistralEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn MistralProvider::embeddingModel(
  self : MistralProvider,
  model_id : MistralEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn language_model(
  self,
  model_id,
) {
  MistralProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn embedding_model(
  self,
  model_id,
) {
  MistralProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn speech_model(
  self,
  model_id,
) {
  Some(MistralProvider::speech_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn transcription_model(
  self,
  model_id,
) {
  Some(MistralProvider::transcription_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for MistralProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Mistral language model directly.
pub fn mistral(
  model_id : MistralChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.mistral.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_mistral(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

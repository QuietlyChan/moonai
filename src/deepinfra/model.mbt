///|
/// DeepInfra provider settings.
pub struct DeepInfraProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a DeepInfra provider. The API key defaults to the
/// `DEEPINFRA_API_KEY` environment variable.
pub fn create_deepinfra(
  api_key? : String = "",
  base_url? : String = "https://api.deepinfra.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> DeepInfraProvider {
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
pub fn createDeepInfra(
  api_key? : String = "",
  base_url? : String = "https://api.deepinfra.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> DeepInfraProvider {
  create_deepinfra(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a DeepInfra chat model.
pub fn DeepInfraProvider::chat(
  self : DeepInfraProvider,
  model_id : DeepInfraChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = deepinfra_chat_value(
    model_id,
    api_key=self.api_key,
    base_url="\{self.base_url}/openai",
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    id_generator=self.id_generator,
  )
  model as &@provider.LanguageModelV4
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn DeepInfraProvider::language_model(
  self : DeepInfraProvider,
  model_id : DeepInfraChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select a DeepInfra completion model.
pub fn DeepInfraProvider::completion_model(
  self : DeepInfraProvider,
  model_id : DeepInfraCompletionModelId,
) -> &@provider.LanguageModelV4 {
  let model = @openai_compatible.OpenAICompatibleCompletionLanguageModel::new(
    model_id,
    @openai_compatible.OpenAICompatibleCompletionConfig::new(
      provider_name="deepinfra.completion",
      base_url="\{self.base_url}/openai",
      api_key=self.api_key,
      api_key_environment_variable="DEEPINFRA_API_KEY",
      headers=self.headers,
      idle_timeout_ms=self.idle_timeout_ms,
      http_transport=self.http_transport,
    ),
  )
  model as &@provider.LanguageModelV4
}

///|
/// Camel-case alias for `completion_model`.
pub fn DeepInfraProvider::completionModel(
  self : DeepInfraProvider,
  model_id : DeepInfraCompletionModelId,
) -> &@provider.LanguageModelV4 {
  self.completion_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn DeepInfraProvider::chatModel(
  self : DeepInfraProvider,
  model_id : DeepInfraChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select a DeepInfra embedding model.
pub fn DeepInfraProvider::embedding(
  self : DeepInfraProvider,
  model_id : DeepInfraEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = @openai_compatible.openai_compatible_embedding(
    provider_name="deepinfra",
    base_url="\{self.base_url}/openai",
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    api_key_environment_variable="DEEPINFRA_API_KEY",
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.EmbeddingModelV4
}

///|
/// Alias for `embedding`.
pub fn DeepInfraProvider::embedding_model(
  self : DeepInfraProvider,
  model_id : DeepInfraEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn DeepInfraProvider::embeddingModel(
  self : DeepInfraProvider,
  model_id : DeepInfraEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Select a DeepInfra image model.
pub fn DeepInfraProvider::image(
  self : DeepInfraProvider,
  model_id : DeepInfraImageModelId,
) -> &@provider.ImageModelV4 {
  let model = deepinfra_image_value(
    model_id,
    api_key=self.api_key,
    base_url="\{self.base_url}/inference",
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.ImageModelV4
}

///|
/// Alias for `image`.
pub fn DeepInfraProvider::image_model(
  self : DeepInfraProvider,
  model_id : DeepInfraImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
/// Camel-case alias for `image_model`.
pub fn DeepInfraProvider::imageModel(
  self : DeepInfraProvider,
  model_id : DeepInfraImageModelId,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn language_model(
  self,
  model_id,
) {
  DeepInfraProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn embedding_model(
  self,
  model_id,
) {
  DeepInfraProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn image_model(
  self,
  model_id,
) {
  DeepInfraProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for DeepInfraProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 DeepInfra language model directly.
pub fn deepinfra(
  model_id : DeepInfraChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.deepinfra.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_deepinfra(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

///|
/// TogetherAI provider settings.
pub struct TogetherAIProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Only this model id currently supports structured outputs on TogetherAI.
pub fn get_model_structured_output_support(model_id : String) -> Bool {
  model_id == "deepseek-ai/DeepSeek-V4-Flash-0731"
}

///|
/// Camel-case spelling of `get_model_structured_output_support`.
pub fn getModelStructuredOutputSupport(model_id : String) -> Bool {
  get_model_structured_output_support(model_id)
}

///|
/// Create a TogetherAI provider. The API key defaults to the
/// `TOGETHER_API_KEY` environment variable.
pub fn create_togetherai(
  api_key? : String = "",
  base_url? : String = "https://api.together.xyz/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> TogetherAIProvider {
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
pub fn createTogetherAI(
  api_key? : String = "",
  base_url? : String = "https://api.together.xyz/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> TogetherAIProvider {
  create_togetherai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
fn TogetherAIProvider::chat_value(
  self : TogetherAIProvider,
  model_id : TogetherAIChatModelId,
) -> @openai_compatible.OpenAICompatibleChatLanguageModel {
  @openai_compatible.OpenAICompatibleChatLanguageModel::new(
    model_id,
    @openai_compatible.OpenAICompatibleChatConfig::new(
      provider_name="togetherai.chat",
      base_url=self.base_url,
      api_key=self.api_key,
      api_key_environment_variable="TOGETHER_API_KEY",
      headers=self.headers,
      include_usage=true,
      supports_structured_outputs=get_model_structured_output_support(model_id),
      idle_timeout_ms=self.idle_timeout_ms,
      http_transport=self.http_transport,
      id_generator=self.id_generator,
    ),
  )
}

///|
/// Select a TogetherAI chat model.
pub fn TogetherAIProvider::chat(
  self : TogetherAIProvider,
  model_id : TogetherAIChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.chat_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn TogetherAIProvider::language_model(
  self : TogetherAIProvider,
  model_id : TogetherAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Construct the concrete completion model behind the public V4 boundary.
fn TogetherAIProvider::completion_model_value(
  self : TogetherAIProvider,
  model_id : TogetherAICompletionModelId,
) -> @openai_compatible.OpenAICompatibleCompletionLanguageModel {
  @openai_compatible.OpenAICompatibleCompletionLanguageModel::new(
    model_id,
    @openai_compatible.OpenAICompatibleCompletionConfig::new(
      provider_name="togetherai.completion",
      base_url=self.base_url,
      api_key=self.api_key,
      api_key_environment_variable="TOGETHER_API_KEY",
      headers=self.headers,
      include_usage=true,
      idle_timeout_ms=self.idle_timeout_ms,
      http_transport=self.http_transport,
    ),
  )
}

///|
/// Select a TogetherAI completion model.
pub fn TogetherAIProvider::completion_model(
  self : TogetherAIProvider,
  model_id : TogetherAICompletionModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.completion_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// Camel-case alias for `completion_model`.
pub fn TogetherAIProvider::completionModel(
  self : TogetherAIProvider,
  model_id : TogetherAICompletionModelId,
) -> &@provider.LanguageModelV4 {
  self.completion_model(model_id)
}

///|
/// Select a TogetherAI embedding model.
pub fn TogetherAIProvider::embedding(
  self : TogetherAIProvider,
  model_id : TogetherAIEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = @openai_compatible.openai_compatible_embedding(
    provider_name="togetherai",
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    api_key_environment_variable="TOGETHER_API_KEY",
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.EmbeddingModelV4
}

///|
/// Alias for `embedding`.
pub fn TogetherAIProvider::embedding_model(
  self : TogetherAIProvider,
  model_id : TogetherAIEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn TogetherAIProvider::embeddingModel(
  self : TogetherAIProvider,
  model_id : TogetherAIEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Construct the concrete image model behind the public V4 boundary.
fn TogetherAIProvider::image_model_value(
  self : TogetherAIProvider,
  model_id : TogetherAIImageModelId,
) -> TogetherAIImageModel {
  togetherai_image_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a TogetherAI image model.
pub fn TogetherAIProvider::image(
  self : TogetherAIProvider,
  model_id : TogetherAIImageModelId,
) -> &@provider.ImageModelV4 {
  let model = self.image_model_value(model_id)
  model as &@provider.ImageModelV4
}

///|
/// Alias for `image`.
pub fn TogetherAIProvider::image_model(
  self : TogetherAIProvider,
  model_id : TogetherAIImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
/// Camel-case alias for `image_model`.
pub fn TogetherAIProvider::imageModel(
  self : TogetherAIProvider,
  model_id : TogetherAIImageModelId,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
/// Construct the concrete reranking model behind the public V4 boundary.
fn TogetherAIProvider::reranking_model_value(
  self : TogetherAIProvider,
  model_id : TogetherAIRerankingModelId,
) -> TogetherAIRerankingModel {
  togetherai_reranking_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a TogetherAI reranking model.
pub fn TogetherAIProvider::reranking(
  self : TogetherAIProvider,
  model_id : TogetherAIRerankingModelId,
) -> &@provider.RerankingModelV4 {
  let model = self.reranking_model_value(model_id)
  model as &@provider.RerankingModelV4
}

///|
/// Alias for `reranking`.
pub fn TogetherAIProvider::reranking_model(
  self : TogetherAIProvider,
  model_id : TogetherAIRerankingModelId,
) -> &@provider.RerankingModelV4 {
  self.reranking(model_id)
}

///|
/// Camel-case alias for `reranking_model`.
pub fn TogetherAIProvider::rerankingModel(
  self : TogetherAIProvider,
  model_id : TogetherAIRerankingModelId,
) -> &@provider.RerankingModelV4 {
  self.reranking_model(model_id)
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn language_model(
  self,
  model_id,
) {
  TogetherAIProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn embedding_model(
  self,
  model_id,
) {
  TogetherAIProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn reranking_model(
  self,
  model_id,
) {
  Some(TogetherAIProvider::reranking(self, model_id))
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn image_model(
  self,
  model_id,
) {
  TogetherAIProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for TogetherAIProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 TogetherAI language model directly.
pub fn togetherai(
  model_id : TogetherAIChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.together.xyz/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_togetherai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

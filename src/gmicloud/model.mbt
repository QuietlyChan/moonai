///|
/// GMI Cloud provider settings.
pub struct GmicloudProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a GMI Cloud provider. The API key defaults to the
/// `GMI_CLOUD_APIKEY` environment variable (matching GMI's own SDK package).
pub fn create_gmicloud(
  api_key? : String = "",
  base_url? : String = "https://api.gmi-serving.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> GmicloudProvider {
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
pub fn createGmicloud(
  api_key? : String = "",
  base_url? : String = "https://api.gmi-serving.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> GmicloudProvider {
  create_gmicloud(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a GMI Cloud chat model.
pub fn GmicloudProvider::chat(
  self : GmicloudProvider,
  model_id : GmicloudChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = @openai_compatible.OpenAICompatibleChatLanguageModel::new(
    model_id,
    @openai_compatible.OpenAICompatibleChatConfig::new(
      provider_name="gmicloud.chat",
      base_url=self.base_url,
      api_key=self.api_key,
      api_key_environment_variable="GMI_CLOUD_APIKEY",
      headers=self.headers,
      include_usage=true,
      error_structure=gmicloud_error_structure(),
      idle_timeout_ms=self.idle_timeout_ms,
      http_transport=self.http_transport,
      id_generator=self.id_generator,
    ),
  )
  model as &@provider.LanguageModelV4
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn GmicloudProvider::language_model(
  self : GmicloudProvider,
  model_id : GmicloudChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn GmicloudProvider::languageModel(
  self : GmicloudProvider,
  model_id : GmicloudChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn GmicloudProvider::chatModel(
  self : GmicloudProvider,
  model_id : GmicloudChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn language_model(
  self,
  model_id,
) {
  GmicloudProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for GmicloudProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 GMI Cloud language model directly.
pub fn gmicloud(
  model_id : GmicloudChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.gmi-serving.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_gmicloud(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

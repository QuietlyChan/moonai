///|
/// Hugging Face provider settings.
pub struct HuggingFaceProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Hugging Face provider. The API key defaults to the
/// `HUGGINGFACE_API_KEY` environment variable. The provider serves the
/// OpenAI Responses wire protocol through the HF router, so the protocol
/// implementation is shared with the OpenAI package.
pub fn create_huggingface(
  api_key? : String = "",
  base_url? : String = "https://router.huggingface.co/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> HuggingFaceProvider {
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
pub fn createHuggingFace(
  api_key? : String = "",
  base_url? : String = "https://router.huggingface.co/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> HuggingFaceProvider {
  create_huggingface(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select a Hugging Face Responses model.
pub fn HuggingFaceProvider::responses(
  self : HuggingFaceProvider,
  model_id : HuggingFaceResponsesModelId,
) -> &@provider.LanguageModelV4 raise {
  self.language_model(model_id)
}

///|
/// Select a Hugging Face language model (Responses wire protocol).
pub fn HuggingFaceProvider::language_model(
  self : HuggingFaceProvider,
  model_id : HuggingFaceResponsesModelId,
) -> &@provider.LanguageModelV4 raise {
  @openai.openai_responses_language_model({
    provider_name: "huggingface.responses",
    url: @provider_utils.append_path(self.base_url, "/responses"),
    api_key: @provider_utils.load_api_key(
      self.api_key,
      environment_variable_name="HUGGINGFACE_API_KEY",
      description="Hugging Face",
    ),
    model_id,
    headers: self.headers,
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    http_transport: self.http_transport,
  })
}

///|
/// Camel-case alias for `language_model`.
pub fn HuggingFaceProvider::languageModel(
  self : HuggingFaceProvider,
  model_id : HuggingFaceResponsesModelId,
) -> &@provider.LanguageModelV4 raise {
  self.language_model(model_id)
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn language_model(
  self,
  model_id,
) {
  HuggingFaceProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for HuggingFaceProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Hugging Face language model directly.
pub fn huggingface(
  model_id : HuggingFaceResponsesModelId,
  api_key? : String = "",
  base_url? : String = "https://router.huggingface.co/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 raise {
  create_huggingface(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

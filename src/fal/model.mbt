///|
/// fal provider settings.
pub struct FalProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a fal provider. The API key defaults to the `FAL_API_KEY`
/// environment variable.
pub fn create_fal(
  api_key? : String = "",
  base_url? : String = "https://fal.run",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> FalProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createFal(
  api_key? : String = "",
  base_url? : String = "https://fal.run",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> FalProvider {
  create_fal(api_key~, base_url~, headers~, idle_timeout_ms~, http_transport?)
}

///|
/// Select a fal image model (synchronous execution endpoint).
pub fn FalProvider::image(
  self : FalProvider,
  model_id : FalImageModelId,
) -> &@provider.ImageModelV4 {
  let model = fal_image_value(
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
pub fn FalProvider::image_model(
  self : FalProvider,
  model_id : FalImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
/// Camel-case alias for `image_model`.
pub fn FalProvider::imageModel(
  self : FalProvider,
  model_id : FalImageModelId,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn image_model(
  self,
  model_id,
) {
  FalProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for FalProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 fal image model directly.
pub fn fal(
  model_id : FalImageModelId,
  api_key? : String = "",
  base_url? : String = "https://fal.run",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.ImageModelV4 {
  create_fal(api_key~, base_url~, headers~, idle_timeout_ms~, http_transport?).image(
    model_id,
  )
}

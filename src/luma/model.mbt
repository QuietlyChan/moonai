///|
/// Luma provider settings.
pub struct LumaProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv poll_interval_ms : Int
  priv max_poll_attempts : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Luma provider. The API key defaults to the `LUMAAI_API_KEY`
/// environment variable.
pub fn create_luma(
  api_key? : String = "",
  base_url? : String = "https://api.lumalabs.ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = LUMA_POLL_INTERVAL_MS,
  max_poll_attempts? : Int = LUMA_MAX_POLL_ATTEMPTS,
  http_transport? : &@provider_utils.HttpTransport,
) -> LumaProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    poll_interval_ms,
    max_poll_attempts,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createLuma(
  api_key? : String = "",
  base_url? : String = "https://api.lumalabs.ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = LUMA_POLL_INTERVAL_MS,
  max_poll_attempts? : Int = LUMA_MAX_POLL_ATTEMPTS,
  http_transport? : &@provider_utils.HttpTransport,
) -> LumaProvider {
  create_luma(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    poll_interval_ms~,
    max_poll_attempts~,
    http_transport?,
  )
}

///|
/// Select a Luma image model.
pub fn LumaProvider::image(
  self : LumaProvider,
  model_id : LumaImageModelId,
) -> &@provider.ImageModelV4 {
  let model = luma_image_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    poll_interval_ms=self.poll_interval_ms,
    max_poll_attempts=self.max_poll_attempts,
    http_transport=self.http_transport,
  )
  model as &@provider.ImageModelV4
}

///|
/// Alias for `image`.
pub fn LumaProvider::image_model(
  self : LumaProvider,
  model_id : LumaImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
/// Camel-case alias for `image_model`.
pub fn LumaProvider::imageModel(
  self : LumaProvider,
  model_id : LumaImageModelId,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn image_model(
  self,
  model_id,
) {
  LumaProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for LumaProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Luma image model directly.
pub fn luma(
  model_id : LumaImageModelId,
  api_key? : String = "",
  base_url? : String = "https://api.lumalabs.ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = LUMA_POLL_INTERVAL_MS,
  max_poll_attempts? : Int = LUMA_MAX_POLL_ATTEMPTS,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.ImageModelV4 {
  create_luma(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    poll_interval_ms~,
    max_poll_attempts~,
    http_transport?,
  ).image(model_id)
}

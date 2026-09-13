///|
/// Black Forest Labs provider settings.
pub struct BflProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv poll_interval_ms : Int
  priv poll_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Black Forest Labs provider. The API key defaults to the
/// `BFL_API_KEY` environment variable.
pub fn create_bfl(
  api_key? : String = "",
  base_url? : String = "https://api.bfl.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = BFL_POLL_INTERVAL_MS,
  poll_timeout_ms? : Int = BFL_POLL_TIMEOUT_MS,
  http_transport? : &@provider_utils.HttpTransport,
) -> BflProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    poll_interval_ms,
    poll_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createBfl(
  api_key? : String = "",
  base_url? : String = "https://api.bfl.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = BFL_POLL_INTERVAL_MS,
  poll_timeout_ms? : Int = BFL_POLL_TIMEOUT_MS,
  http_transport? : &@provider_utils.HttpTransport,
) -> BflProvider {
  create_bfl(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    poll_interval_ms~,
    poll_timeout_ms~,
    http_transport?,
  )
}

///|
/// Select a Black Forest Labs image model.
pub fn BflProvider::image(
  self : BflProvider,
  model_id : BflImageModelId,
) -> &@provider.ImageModelV4 {
  let model = bfl_image_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    poll_interval_ms=self.poll_interval_ms,
    poll_timeout_ms=self.poll_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.ImageModelV4
}

///|
/// Alias for `image`.
pub fn BflProvider::image_model(
  self : BflProvider,
  model_id : BflImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
/// Camel-case alias for `image_model`.
pub fn BflProvider::imageModel(
  self : BflProvider,
  model_id : BflImageModelId,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn image_model(
  self,
  model_id,
) {
  BflProvider::image_model(self, model_id)
}

///|
/// Select a Black Forest Labs video model.
pub fn BflProvider::video(
  self : BflProvider,
  model_id : String,
) -> &@provider.VideoModelV4 {
  let model = bfl_video_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    poll_interval_ms=self.poll_interval_ms,
    poll_timeout_ms=self.poll_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.VideoModelV4
}

///|
/// Alias for `video`.
pub fn BflProvider::video_model(
  self : BflProvider,
  model_id : String,
) -> &@provider.VideoModelV4 {
  self.video(model_id)
}

///|
/// Camel-case alias for `video_model`.
pub fn BflProvider::videoModel(
  self : BflProvider,
  model_id : String,
) -> &@provider.VideoModelV4 {
  self.video_model(model_id)
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for BflProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Black Forest Labs image model directly.
pub fn bfl(
  model_id : BflImageModelId,
  api_key? : String = "",
  base_url? : String = "https://api.bfl.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = BFL_POLL_INTERVAL_MS,
  poll_timeout_ms? : Int = BFL_POLL_TIMEOUT_MS,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.ImageModelV4 {
  create_bfl(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    poll_interval_ms~,
    poll_timeout_ms~,
    http_transport?,
  ).image(model_id)
}

///|
/// Prodia provider settings.
pub struct ProdiaProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Prodia provider. The API key defaults to the `PRODIA_TOKEN`
/// environment variable.
pub fn create_prodia(
  api_key? : String = "",
  base_url? : String = "https://inference.prodia.com/v2",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 300_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> ProdiaProvider {
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
pub fn createProdia(
  api_key? : String = "",
  base_url? : String = "https://inference.prodia.com/v2",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 300_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> ProdiaProvider {
  create_prodia(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

///|
/// Select a Prodia image model.
pub fn ProdiaProvider::image(
  self : ProdiaProvider,
  model_id : ProdiaImageModelId,
) -> &@provider.ImageModelV4 {
  let model = prodia_image_value(
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
pub fn ProdiaProvider::image_model(
  self : ProdiaProvider,
  model_id : ProdiaImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
/// Camel-case alias for `image_model`.
pub fn ProdiaProvider::imageModel(
  self : ProdiaProvider,
  model_id : ProdiaImageModelId,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
/// Select a Prodia video model.
pub fn ProdiaProvider::video(
  self : ProdiaProvider,
  model_id : ProdiaVideoModelId,
) -> &@provider.VideoModelV4 {
  let model = prodia_video_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.VideoModelV4
}

///|
/// Alias for `video`.
pub fn ProdiaProvider::video_model(
  self : ProdiaProvider,
  model_id : ProdiaVideoModelId,
) -> &@provider.VideoModelV4 {
  self.video(model_id)
}

///|
/// Camel-case alias for `video_model`.
pub fn ProdiaProvider::videoModel(
  self : ProdiaProvider,
  model_id : ProdiaVideoModelId,
) -> &@provider.VideoModelV4 {
  self.video_model(model_id)
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
/// Select a Prodia language model.
pub fn ProdiaProvider::language_model(
  self : ProdiaProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 {
  let model = prodia_language_model_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.LanguageModelV4
}

///|
/// Camel-case alias for `language_model`.
pub fn ProdiaProvider::languageModel(
  self : ProdiaProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn language_model(
  self,
  model_id,
) {
  ProdiaProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn image_model(
  self,
  model_id,
) {
  ProdiaProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for ProdiaProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 Prodia image model directly.
pub fn prodia(
  model_id : ProdiaImageModelId,
  api_key? : String = "",
  base_url? : String = "https://inference.prodia.com/v2",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 300_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.ImageModelV4 {
  create_prodia(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).image(model_id)
}

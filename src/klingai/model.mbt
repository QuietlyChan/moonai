///|
/// KlingAI provider settings.
pub struct KlingaiProvider {
  priv auth_token : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a KlingAI provider. Authentication resolves in order: the
/// `api_key` argument or `KLINGAI_API_KEY` environment variable as a direct
/// bearer token, or the `KLINGAI_ACCESS_KEY` + `KLINGAI_SECRET_KEY` pair
/// signed into a short-lived HS256 JWT.
pub fn create_klingai(
  api_key? : String,
  access_key? : String,
  secret_key? : String,
  base_url? : String = "https://api-singapore.klingai.com",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> KlingaiProvider raise @provider.LoadAPIKeyError {
  {
    auth_token: resolve_klingai_auth_token(api_key?, access_key?, secret_key?),
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
pub fn createKlingai(
  api_key? : String,
  access_key? : String,
  secret_key? : String,
  base_url? : String = "https://api-singapore.klingai.com",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> KlingaiProvider raise @provider.LoadAPIKeyError {
  create_klingai(
    api_key?,
    access_key?,
    secret_key?,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

///|
/// Select a KlingAI video generation model.
pub fn KlingaiProvider::video(
  self : KlingaiProvider,
  model_id : KlingaiVideoModelId,
) -> &@provider.VideoModelV4 {
  let model = klingai_video_value(
    model_id,
    auth_token=self.auth_token,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.VideoModelV4
}

///|
/// Alias for `video`.
pub fn KlingaiProvider::video_model(
  self : KlingaiProvider,
  model_id : KlingaiVideoModelId,
) -> &@provider.VideoModelV4 {
  self.video(model_id)
}

///|
/// Camel-case alias for `video_model`.
pub fn KlingaiProvider::videoModel(
  self : KlingaiProvider,
  model_id : KlingaiVideoModelId,
) -> &@provider.VideoModelV4 {
  self.video_model(model_id)
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for KlingaiProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 KlingAI video model directly.
pub fn klingai(
  model_id : KlingaiVideoModelId,
  api_key? : String,
  access_key? : String,
  secret_key? : String,
  base_url? : String = "https://api-singapore.klingai.com",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.VideoModelV4 raise @provider.LoadAPIKeyError {
  create_klingai(
    api_key?,
    access_key?,
    secret_key?,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).video(model_id)
}

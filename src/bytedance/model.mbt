///|
/// ByteDance ModelArk provider factory.
pub struct ByteDanceProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a ByteDance ModelArk provider.
pub fn create_byte_dance(
  api_key? : String = "",
  base_url? : String = "https://ark.ap-southeast.bytepluses.com/api/v3",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> ByteDanceProvider {
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
/// AI SDK-style provider factory.
pub fn createByteDance(
  api_key? : String = "",
  base_url? : String = "https://ark.ap-southeast.bytepluses.com/api/v3",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> ByteDanceProvider {
  create_byte_dance(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

///|
fn ByteDanceProvider::image_model_value(
  self : ByteDanceProvider,
  model_id : ByteDanceImageModelId,
) -> ByteDanceImageModel {
  ByteDanceImageModel::new(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a Seedream image model.
pub fn ByteDanceProvider::image(
  self : ByteDanceProvider,
  model_id : ByteDanceImageModelId,
) -> &@provider.ImageModelV4 {
  let model = self.image_model_value(model_id)
  model as &@provider.ImageModelV4
}

///|
/// AI SDK-style image selector.
pub fn ByteDanceProvider::imageModel(
  self : ByteDanceProvider,
  model_id : ByteDanceImageModelId,
) -> &@provider.ImageModelV4 {
  self.image(model_id)
}

///|
fn ByteDanceProvider::video_model_value(
  self : ByteDanceProvider,
  model_id : ByteDanceVideoModelId,
) -> ByteDanceVideoModel {
  ByteDanceVideoModel::new(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a Seedance video model.
pub fn ByteDanceProvider::video(
  self : ByteDanceProvider,
  model_id : ByteDanceVideoModelId,
) -> &@provider.VideoModelV4 {
  let model = self.video_model_value(model_id)
  model as &@provider.VideoModelV4
}

///|
/// AI SDK-style video selector.
pub fn ByteDanceProvider::videoModel(
  self : ByteDanceProvider,
  model_id : ByteDanceVideoModelId,
) -> &@provider.VideoModelV4 {
  self.video(model_id)
}

///|
/// Direct Seedream model factory.
pub fn byte_dance_image(
  model_id : ByteDanceImageModelId,
  api_key? : String = "",
  base_url? : String = "https://ark.ap-southeast.bytepluses.com/api/v3",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.ImageModelV4 {
  create_byte_dance(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).image(model_id)
}

///|
/// Direct Seedance model factory.
pub fn byte_dance_video(
  model_id : ByteDanceVideoModelId,
  api_key? : String = "",
  base_url? : String = "https://ark.ap-southeast.bytepluses.com/api/v3",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.VideoModelV4 {
  create_byte_dance(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).video(model_id)
}

///|
/// AI SDK-style direct Seedream model factory.
pub fn byteDanceImage(
  model_id : ByteDanceImageModelId,
  api_key? : String = "",
  base_url? : String = "https://ark.ap-southeast.bytepluses.com/api/v3",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.ImageModelV4 {
  byte_dance_image(
    model_id,
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

///|
/// AI SDK-style direct Seedance model factory.
pub fn byteDanceVideo(
  model_id : ByteDanceVideoModelId,
  api_key? : String = "",
  base_url? : String = "https://ark.ap-southeast.bytepluses.com/api/v3",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.VideoModelV4 {
  byte_dance_video(
    model_id,
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

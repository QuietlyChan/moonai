///|
/// An image model using the OpenAI image generation wire protocol.
pub struct OpenAICompatibleImageModel {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv max_images : Int
  priv include_response_format : Bool
  priv idle_timeout_ms : Int
}

///|
/// Construct an OpenAI-compatible image model directly.
pub fn openai_compatible_image(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  max_images_per_call? : Int = 10,
  include_response_format? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleImageModel {
  {
    provider_name: "\{provider_name}.image",
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    headers: @provider_utils.copy_headers(headers),
    max_images: max_images_per_call,
    include_response_format,
    idle_timeout_ms,
  }
}

///|
fn OpenAICompatibleImageModel::generations_url(
  self : OpenAICompatibleImageModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/images/generations")
}

///|
fn OpenAICompatibleImageModel::request_headers(
  self : OpenAICompatibleImageModel,
) -> Map[String, String] {
  let headers = @provider_utils.copy_headers(self.headers)
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  if self.api_key != "" {
    headers["Authorization"] = "Bearer \{self.api_key}"
  }
  headers
}

///|
pub impl @moonai.ImageModel for OpenAICompatibleImageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @moonai.ImageModel for OpenAICompatibleImageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @moonai.ImageModel for OpenAICompatibleImageModel with fn max_images_per_call(
  self,
) -> Int {
  self.max_images
}

///|
pub impl @moonai.ImageModel for OpenAICompatibleImageModel with fn generate(
  self,
  options,
) {
  self.generate_images(options)
}

///|
async fn OpenAICompatibleImageModel::generate_images(
  self : OpenAICompatibleImageModel,
  options : @moonai.ImageCallOptions,
) -> @moonai.ImageResponse {
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.generations_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=encode_image_request(
      self.model_id,
      options,
      include_response_format=self.include_response_format,
    ),
    timeout_ms=self.idle_timeout_ms,
  )
  decode_image_response(response)
}

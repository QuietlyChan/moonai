///|
/// ByteDance Seedream image model.
pub struct ByteDanceImageModel {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv model_id_value : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct a Seedream image model.
pub fn ByteDanceImageModel::new(
  model_id : ByteDanceImageModelId,
  api_key? : String = "",
  base_url? : String = "https://ark.ap-southeast.bytepluses.com/api/v3",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> ByteDanceImageModel {
  {
    provider_name: "bytedance.image",
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id_value: model_id,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
fn ByteDanceImageModel::create_body(
  self : ByteDanceImageModel,
  options : @provider.ImageModelV4CallOptions,
  provider_options : ByteDanceImageModelOptions,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id_value)),
    ("response_format", Json::string("b64_json")),
  ])
  if options.prompt is Some(value) {
    fields["prompt"] = Json::string(value)
  }
  let files = options.files.unwrap_or([])
  if files.length() == 1 {
    fields["image"] = Json::string(
      @provider_utils.convert_image_model_file_to_data_uri(files[0]),
    )
  } else if files.length() > 1 {
    fields["image"] = Json::array(
      [
        for file in files => {
          Json::string(
            @provider_utils.convert_image_model_file_to_data_uri(file),
          )
        }
      ],
    )
  }
  if options.size is Some(value) {
    fields["size"] = Json::string(value)
  }
  if provider_options.watermark is Some(value) {
    fields["watermark"] = Json::boolean(value)
  }
  if provider_options.output_format is Some(value) {
    fields["output_format"] = Json::string(value)
  }
  if provider_options.size is Some(value) {
    fields["size"] = Json::string(value)
  }
  if provider_options.sequential_image_generation is Some(value) {
    fields["sequential_image_generation"] = Json::string(value)
  }
  if provider_options.max_images is Some(value) {
    fields["sequential_image_generation_options"] = { "max_images": value }
  }
  if provider_options.optimize_prompt_mode is Some(value) {
    fields["optimize_prompt_options"] = { "mode": value }
  }
  for entry in provider_options.extensions.iter2() {
    fields[entry.0] = entry.1
  }
  // The SDK must receive actual image bytes; provider options cannot override
  // this transport-owned field.
  fields["response_format"] = Json::string("b64_json")
  Json::object(fields)
}

///|
fn decode_bytedance_images(
  json : Json,
) -> Array[@provider.GeneratedImage] raise {
  match json {
    { "data": Array(values), .. } => {
      let images : Array[@provider.GeneratedImage] = []
      for value in values {
        match value {
          { "b64_json": String(data), .. } if data != "" =>
            images.push(@provider.GeneratedImage::new(@provider.Base64(data)))
          _ =>
            raise @provider.InvalidResponseDataError(
              message="ByteDance image response item did not contain b64_json",
              data=value,
            )
        }
      }
      images
    }
    _ =>
      raise @provider.InvalidResponseDataError(
        message="ByteDance image response did not contain data",
        data=json,
      )
  }
}

///|
async fn ByteDanceImageModel::generate(
  self : ByteDanceImageModel,
  options : @provider.ImageModelV4CallOptions,
) -> @provider.ImageModelV4Result {
  let (provider_options, option_warnings) = parse_bytedance_image_options(
    options.provider_options,
  )
  let warnings = option_warnings
  if options.aspect_ratio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="ByteDance uses size or providerOptions.bytedance.size instead.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(@provider.Warning::unsupported("seed"))
  }
  if options.mask is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="mask",
        details="Seedream accepts edit instructions and input images, but no separate mask.",
      ),
    )
  }
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/images/generations"),
    headers=bytedance_headers(self.api_key, self.headers, options.headers),
    body=self.create_body(options, provider_options),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=bytedance_error_message,
    transport=self.http_transport,
  )
  let images = @provider_utils.handle_json_response(
    response, decode_bytedance_images,
  )
  @provider.ImageModelV4Result::new(
    images,
    warnings~,
    request=response.request,
    response=@provider.merge_response_metadata(
      Some(response.response),
      @provider.ResponseMetadata::new(
        model_id=self.model_id_value,
        created_at=(@env.now() / 1000UL).to_int(),
      ),
    ),
  )
}

///|
pub impl @provider.ImageModelV4 for ByteDanceImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for ByteDanceImageModel with fn provider(self) {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for ByteDanceImageModel with fn model_id(self) {
  self.model_id_value
}

///|
pub impl @provider.ImageModelV4 for ByteDanceImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.ImageModelV4 for ByteDanceImageModel with fn do_generate(
  self,
  options,
) {
  self.generate(options)
}

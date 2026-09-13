///|
/// The AI Gateway image model: POST /image-model; images always come back
/// as Base64 strings over the wire.
struct GatewayImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn gateway_image_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewayImageModel {
  {
    provider_name: "gateway",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn GatewayImageModel::image_headers(
  self : GatewayImageModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let resolved = gateway_base_headers(
    api_key=self.api_key,
    headers=self.headers,
    extra~,
    content_type="application/json",
    accept="application/json",
  )
  resolved["ai-image-model-specification-version"] = "4"
  resolved["ai-model-id"] = self.model_id
  resolved
}

///|
/// Encode an input image file for the JSON wire: inline bytes become
/// Base64, URLs pass through.
fn gateway_encode_image_file(file : @provider.ImageModelV4File) -> Json raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  fn data_object(fields : Array[(String, Json)]) -> Map[String, Json] {
    let map : Map[String, Json] = Map([])
    for entry in fields {
      map[entry.0] = entry.1
    }
    map
  }

  let media_type_and_data : (String, Json) = match file {
    @provider.ImageV4Data(data~, media_type~) =>
      (
        media_type,
        Json::object(
          data_object([
            ("type", Json::string("data")),
            ("data", Json::string(data)),
          ]),
        ),
      )
    @provider.ImageV4Bytes(data~, media_type~) =>
      (
        media_type,
        Json::object(
          data_object([
            ("type", Json::string("data")),
            ("data", Json::string(@base64.encode(data, padding=true))),
          ]),
        ),
      )
    @provider.ImageV4Url(url~) =>
      (
        "image/*",
        Json::object(
          data_object([
            ("type", Json::string("url")),
            ("url", Json::string(url)),
          ]),
        ),
      )
  }
  let (media_type, data) = media_type_and_data
  Json::object(
    data_object([
      ("type", Json::string("file")),
      ("mediaType", Json::string(media_type)),
      ("data", data),
    ]),
  )
}

///|
/// Decode the image response: every entry is a Base64 payload.
fn gateway_decode_image_response(
  value : Json,
) -> Array[@provider.GeneratedImage] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match value {
    { "images": Array(items), .. } => {
      let images : Array[@provider.GeneratedImage] = []
      for item in items {
        match item {
          String(data) =>
            images.push(
              @provider.GeneratedImage::new(@provider.ImageData::Base64(data)),
            )
          _ => fail("gateway image response has malformed entries")
        }
      }
      images
    }
    _ => fail("gateway image response missing images")
  }
}

///|
pub impl @provider.ImageModelV4 for GatewayImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for GatewayImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for GatewayImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for GatewayImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  None
}

///|
pub impl @provider.ImageModelV4 for GatewayImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let fields : Map[String, Json] = Map([])
  if options.prompt is Some(value) {
    fields["prompt"] = Json::string(value)
  }
  fields["n"] = Json::number(options.n.to_double())
  if options.size is Some(value) {
    fields["size"] = Json::string(value)
  }
  if options.aspect_ratio is Some(value) {
    fields["aspectRatio"] = Json::string(value)
  }
  if options.seed is Some(value) {
    fields["seed"] = Json::number(value.to_double())
  }
  if resolution.values.length() > 0 {
    fields["providerOptions"] = Json::object(resolution.values)
  }
  let files = options.files.unwrap_or([])
  if files.length() > 0 {
    let encoded : Array[Json] = []
    for file in files {
      encoded.push(gateway_encode_image_file(file))
    }
    fields["files"] = Json::array(encoded)
  }
  if options.mask is Some(mask) {
    fields["mask"] = gateway_encode_image_file(mask)
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/image-model"),
    headers=self.image_headers(extra=options.headers),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let images = @provider_utils.handle_json_response(
    response, gateway_decode_image_response,
  )
  @provider.ImageModelV4Result::new(
    images,
    warnings~,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    request=response.request,
    response=@provider.merge_response_metadata(
      Some(response.response),
      @provider.ResponseMetadata::new(
        model_id=self.model_id,
        created_at=request_created_at,
      ),
    ),
  )
}

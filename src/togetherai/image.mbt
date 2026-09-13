///|
/// The concrete TogetherAI image model behind the public V4 boundary.
struct TogetherAIImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn togetherai_image_value(
  model_id : TogetherAIImageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> TogetherAIImageModel {
  {
    provider_name: "togetherai.image",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Split a `widthxheight` size string into the two integers TogetherAI
/// expects as `width` and `height`.
fn togetherai_parse_dimension(value : String) -> Int? {
  try @string.parse_int64(value, base=10) catch {
    _ => None
  } noraise {
    parsed if parsed > 0L => Some(parsed.to_int())
    _ => None
  }
}

///|
/// Build the `POST /images/generations` request body.
fn togetherai_image_request_body(
  model_id : String,
  prompt~ : String?,
  seed~ : Int?,
  n~ : Int,
  size~ : String?,
  image_url~ : String?,
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([("model", Json::string(model_id))])
  if prompt is Some(value) {
    fields["prompt"] = Json::string(value)
  }
  if seed is Some(value) {
    fields["seed"] = Json::number(value.to_double())
  }
  if n > 1 {
    fields["n"] = Json::number(n.to_double())
  }
  if size is Some(value) {
    let parts = value.split("x").to_array()
    if parts.length() == 2 {
      match
        (
          togetherai_parse_dimension(parts[0].to_owned()),
          togetherai_parse_dimension(parts[1].to_owned()),
        ) {
        (Some(width), Some(height)) => {
          fields["width"] = Json::number(width.to_double())
          fields["height"] = Json::number(height.to_double())
        }
        _ => ()
      }
    }
  }
  if image_url is Some(value) {
    fields["image_url"] = Json::string(value)
  }
  fields["response_format"] = Json::string("base64")
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
fn decode_togetherai_image_response(
  value : Json,
) -> Array[@provider.GeneratedImage] raise {
  match value {
    { "data": Array(items), .. } => {
      let images : Array[@provider.GeneratedImage] = []
      for item in items {
        match item {
          { "b64_json": String(data), .. } =>
            images.push(
              @provider.GeneratedImage::new(@provider.ImageData::Base64(data)),
            )
          _ => fail("togetherai image response has malformed data items")
        }
      }
      images
    }
    _ => fail("togetherai image response missing data")
  }
}

///|
pub impl @provider.ImageModelV4 for TogetherAIImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for TogetherAIImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for TogetherAIImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for TogetherAIImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.ImageModelV4 for TogetherAIImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  if options.mask is Some(_) {
    fail(
      "Together AI does not support mask-based image editing. Use FLUX Kontext models (e.g., black-forest-labs/FLUX.1-kontext-pro) with a reference image and descriptive prompt instead.",
    )
  }
  if options.size is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="This model does not support the `aspectRatio` option. Use `size` instead.",
      ),
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["togetherai"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let mut image_url : String? = None
  if options.files is Some(files) && files.length() > 0 {
    image_url = Some(
      @provider_utils.convert_image_model_file_to_data_uri(files[0]),
    )
    if files.length() > 1 {
      warnings.push(
        @provider.Warning::Other(
          message="Together AI only supports a single input image. Additional images are ignored.",
        ),
      )
    }
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let request_headers = @provider_utils.merge_headers(
    togetherai_request_headers(
      provider_name=self.provider_name,
      api_key=self.api_key,
      headers=self.headers,
    ),
    options.headers,
  )
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/images/generations"),
    headers=request_headers,
    body=togetherai_image_request_body(
      self.model_id,
      prompt=options.prompt,
      seed=options.seed,
      n=options.n,
      size=options.size,
      image_url~,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=togetherai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let images = @provider_utils.handle_json_response(
    response, decode_togetherai_image_response,
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

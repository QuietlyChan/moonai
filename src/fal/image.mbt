///|
/// The fal image model: synchronous POST https://fal.run/{model} with the
/// images array returned inline.
struct FalImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn fal_image_value(
  model_id : FalImageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> FalImageModel {
  {
    provider_name: "fal.image",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn FalImageModel::request_headers(
  self : FalImageModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="FAL_API_KEY",
    description="fal",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          ("Authorization", "Key \{api_key}"),
          ("Content-Type", "application/json"),
        ]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the generation request body. A single input image uses image_url;
/// multiple inputs use image_urls.
fn fal_image_request_body(
  prompt~ : String,
  n~ : Int,
  aspect_ratio~ : String?,
  image_urls~ : Array[String],
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([("prompt", Json::string(prompt))])
  if n > 1 {
    fields["num_images"] = Json::number(n.to_double())
  }
  if aspect_ratio is Some(value) {
    fields["aspect_ratio"] = Json::string(value)
  }
  if image_urls.length() == 1 {
    fields["image_url"] = Json::string(image_urls[0])
  } else if image_urls.length() > 1 {
    fields["image_urls"] = Json::array(
      [
        for url in image_urls => Json::string(url)
      ],
    )
  }
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
fn decode_fal_image_response(
  value : Json,
) -> Array[@provider.GeneratedImage] raise {
  match value {
    { "images": Array(items), .. } => {
      let images : Array[@provider.GeneratedImage] = []
      for item in items {
        match item {
          { "url": String(url), .. } =>
            images.push(
              @provider.GeneratedImage::new(@provider.ImageData::Url(url)),
            )
          _ => fail("fal image response has malformed images")
        }
      }
      images
    }
    _ => fail("fal image response missing images")
  }
}

///|
pub impl @provider.ImageModelV4 for FalImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for FalImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for FalImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for FalImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  None
}

///|
pub impl @provider.ImageModelV4 for FalImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["fal"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let image_urls : Array[String] = []
  if options.files is Some(files) {
    for file in files {
      image_urls.push(
        @provider_utils.convert_image_model_file_to_data_uri(file),
      )
    }
  }
  if options.mask is Some(mask) {
    image_urls.push(@provider_utils.convert_image_model_file_to_data_uri(mask))
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url="\{self.base_url}/\{self.model_id}",
    headers=self.request_headers(extra=options.headers),
    body=fal_image_request_body(
      prompt=options.prompt.unwrap_or(""),
      n=options.n,
      aspect_ratio=options.aspect_ratio,
      image_urls~,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=fal_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let images = @provider_utils.handle_json_response(
    response, decode_fal_image_response,
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

///|
fn fal_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "detail": Array(items), .. } => {
      let builder = StringBuilder()
      for item in items {
        match item {
          { "msg": String(msg), .. } => {
            builder.write_string(msg)
            builder.write_string("; ")
          }
          _ => ()
        }
      }
      Some(builder.to_string())
    }
    { "detail": String(message), .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}

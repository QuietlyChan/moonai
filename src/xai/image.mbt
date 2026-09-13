///|
/// The xAI image model (/images/generations with moderation enforcement).
struct XaiImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn xai_image_value(
  model_id : XaiImageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> XaiImageModel {
  {
    provider_name: "xai.image",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Build the generation request body. Input images ride along as `image` /
/// `images` URL entries; size is rejected upstream in favor of aspect_ratio.
fn xai_image_request_body(
  model_id : String,
  prompt~ : String?,
  n~ : Int,
  aspect_ratio~ : String?,
  image_urls~ : Array[String],
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([("model", Json::string(model_id))])
  if prompt is Some(value) {
    fields["prompt"] = Json::string(value)
  }
  if n > 1 {
    fields["n"] = Json::number(n.to_double())
  }
  if aspect_ratio is Some(value) {
    fields["aspect_ratio"] = Json::string(value)
  }
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  if image_urls.length() == 1 {
    fields["image"] = { "url": image_urls[0], "type": "image_url" }
  } else if image_urls.length() > 1 {
    fields["images"] = Json::array(
      [
        for url in image_urls => { "url": url, "type": "image_url" }
      ],
    )
  }
  Json::object(fields)
}

///|
/// Decode the response; all-Base64 payloads map directly, otherwise remote
/// URLs are not followed inline and surface as URL images.
fn decode_xai_image_response(
  value : Json,
) -> (Array[@provider.GeneratedImage], Bool) raise {
  match value {
    { "data": Array(items), .. } => {
      let images : Array[@provider.GeneratedImage] = []
      let mut blocked = false
      for item in items {
        if item is { "respect_moderation": False, .. } {
          blocked = true
        }
        match item {
          { "b64_json": String(data), .. } if data != "" =>
            images.push(
              @provider.GeneratedImage::new(@provider.ImageData::Base64(data)),
            )
          { "url": String(url), .. } =>
            images.push(
              @provider.GeneratedImage::new(@provider.ImageData::Url(url)),
            )
          _ => fail("xai image response has malformed data items")
        }
      }
      (images, blocked)
    }
    _ => fail("xai image response missing data")
  }
}

///|
pub impl @provider.ImageModelV4 for XaiImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for XaiImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for XaiImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for XaiImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  Some(3)
}

///|
pub impl @provider.ImageModelV4 for XaiImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  if options.size is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="size",
        details="This model does not support the `size` option. Use `aspectRatio` instead.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(@provider.Warning::unsupported("seed"))
  }
  if options.mask is Some(_) {
    warnings.push(@provider.Warning::unsupported("mask"))
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["xai"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let mut aspect_ratio = options.aspect_ratio
  if resolution.values.get("aspect_ratio") is Some(value) &&
    aspect_ratio is None {
    match value {
      String(text) => aspect_ratio = Some(text)
      _ => ()
    }
  }
  let image_urls : Array[String] = []
  if options.files is Some(files) {
    if files.length() > 10 {
      warnings.push(
        @provider.Warning::Other(
          message="xAI supports a maximum of 10 input images; extra images are ignored.",
        ),
      )
    }
    for index, file in files {
      if index >= 10 {
        break
      }
      image_urls.push(
        @provider_utils.convert_image_model_file_to_data_uri(file),
      )
    }
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/images/generations"),
    headers=xai_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=xai_image_request_body(
      self.model_id,
      prompt=options.prompt,
      n=options.n,
      aspect_ratio~,
      image_urls~,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=xai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (images, blocked) = @provider_utils.handle_json_response(
    response, decode_xai_image_response,
  )
  guard !blocked else {
    fail("Image generation was blocked due to a content policy violation.")
  }
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

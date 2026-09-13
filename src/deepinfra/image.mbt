///|
/// The concrete DeepInfra image model behind the public V4 boundary.
struct DeepInfraImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn deepinfra_image_value(
  model_id : DeepInfraImageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> DeepInfraImageModel {
  {
    provider_name: "deepinfra.image",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn deepinfra_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "detail": { "error": String(message), .. }, .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => Some("Unknown error")
  }
}

///|
/// Strip the data-URI prefix DeepInfra sometimes returns so only the Base64
/// payload remains.
fn deepinfra_strip_data_uri_prefix(value : String) -> String {
  if value.has_prefix("data:image/") {
    match value.find(";base64,") {
      Some(index) => value[index + 8:].to_owned()
      None => value
    }
  } else {
    value
  }
}

///|
/// Build the generation request body. Some DeepInfra models accept `size`,
/// others accept an aspect ratio; pass either through and let the server
/// validate.
fn deepinfra_image_request_body(
  prompt~ : String?,
  n~ : Int,
  aspect_ratio~ : String?,
  size~ : String?,
  seed~ : Int?,
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([])
  if prompt is Some(value) {
    fields["prompt"] = Json::string(value)
  }
  fields["num_images"] = Json::number(n.to_double())
  if aspect_ratio is Some(value) {
    fields["aspect_ratio"] = Json::string(value)
  }
  if size is Some(value) {
    let parts = value.split("x").to_array()
    if parts.length() == 2 {
      fields["width"] = Json::string(parts[0].to_owned())
      fields["height"] = Json::string(parts[1].to_owned())
    }
  }
  if seed is Some(value) {
    fields["seed"] = Json::number(value.to_double())
  }
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
fn decode_deepinfra_image_response(
  value : Json,
) -> Array[@provider.GeneratedImage] raise {
  match value {
    { "images": Array(images), .. } => {
      let result : Array[@provider.GeneratedImage] = []
      for image in images {
        match image {
          String(data) =>
            result.push(
              @provider.GeneratedImage::new(
                @provider.ImageData::Base64(
                  deepinfra_strip_data_uri_prefix(data),
                ),
              ),
            )
          _ => fail("deepinfra image response has malformed images")
        }
      }
      result
    }
    _ => fail("deepinfra image response missing images")
  }
}

///|
fn decode_deepinfra_image_edit_response(
  value : Json,
) -> Array[@provider.GeneratedImage] raise {
  match value {
    { "data": Array(items), .. } => {
      let result : Array[@provider.GeneratedImage] = []
      for item in items {
        match item {
          { "b64_json": String(data), .. } =>
            result.push(
              @provider.GeneratedImage::new(@provider.ImageData::Base64(data)),
            )
          _ => fail("deepinfra image edit response has malformed data items")
        }
      }
      result
    }
    _ => fail("deepinfra image edit response missing data")
  }
}

///|
pub impl @provider.ImageModelV4 for DeepInfraImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for DeepInfraImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for DeepInfraImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for DeepInfraImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.ImageModelV4 for DeepInfraImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["deepinfra"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="DEEPINFRA_API_KEY",
    description=self.provider_name,
  )
  let request_headers = @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(
        Map([
          ("Content-Type", "application/json"),
          ("Authorization", "Bearer \{api_key}"),
        ]),
        self.headers,
      ),
      ["ai-sdk/\{self.provider_name}/\{VERSION}"],
    ),
    options.headers,
  )
  let files = options.files.unwrap_or([])
  let response = if files.length() > 0 {
    // Image editing mode uses the OpenAI-compatible /images/edits endpoint.
    let openai_base = match self.base_url.find("/inference") {
      Some(index) => self.base_url[:index].to_owned()
      None => self.base_url
    }
    let fields : Array[@provider_utils.MultipartField] = [
      @provider_utils.MultipartField::text(name="model", value=self.model_id),
    ]
    if options.prompt is Some(value) {
      fields.push(@provider_utils.MultipartField::text(name="prompt", value~))
    }
    for file in files {
      let resolved = @provider_utils.resolve_image_model_v4_file(
        file,
        provider_name=self.provider_name,
        timeout_ms=self.idle_timeout_ms,
        retry_policy=options.retry_policy,
        cancellation_token?,
        trusted_origin=self.base_url,
        transport=self.http_transport,
      )
      fields.push(
        @provider_utils.MultipartField::file(
          name="image",
          filename=resolved.filename,
          media_type=resolved.media_type,
          data=resolved.data,
        ),
      )
    }
    if options.mask is Some(mask) {
      let resolved = @provider_utils.resolve_image_model_v4_file(
        mask,
        filename="mask",
        provider_name=self.provider_name,
        timeout_ms=self.idle_timeout_ms,
        retry_policy=options.retry_policy,
        cancellation_token?,
        trusted_origin=self.base_url,
        transport=self.http_transport,
      )
      fields.push(
        @provider_utils.MultipartField::file(
          name="mask",
          filename=resolved.filename,
          media_type=resolved.media_type,
          data=resolved.data,
        ),
      )
    }
    fields.push(
      @provider_utils.MultipartField::text(
        name="n",
        value=options.n.to_string(),
      ),
    )
    if options.size is Some(value) {
      fields.push(@provider_utils.MultipartField::text(name="size", value~))
    }
    for entry in resolution.values.iter2() {
      fields.push(
        @provider_utils.MultipartField::text(
          name=entry.0,
          value=entry.1.stringify(),
        ),
      )
    }
    let form_data = @provider_utils.encode_multipart_form_data(fields)
    @provider_utils.post_multipart(
      provider_name=self.provider_name,
      url=@provider_utils.append_path(openai_base, "/images/edits"),
      headers=request_headers,
      form_data~,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=deepinfra_error_to_message,
      is_retryable_response=(_status_code, _error) => None,
      transport=self.http_transport,
    )
  } else {
    @provider_utils.post_json(
      provider_name=self.provider_name,
      url=@provider_utils.append_path(self.base_url, self.model_id),
      headers=request_headers,
      body=deepinfra_image_request_body(
        prompt=options.prompt,
        n=options.n,
        aspect_ratio=options.aspect_ratio,
        size=options.size,
        seed=options.seed,
        provider_options=resolution.values,
      ),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=deepinfra_error_to_message,
      is_retryable_response=(_status_code, _error) => None,
      transport=self.http_transport,
    )
  }
  let images = @provider_utils.handle_json_response(response, value => {
    if files.length() > 0 {
      decode_deepinfra_image_edit_response(value)
    } else {
      decode_deepinfra_image_response(value)
    }
  })
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

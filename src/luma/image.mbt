///|
/// The Luma image model: POST /dream-machine/v1/generations/image then poll
/// the generation until completed.
struct LumaImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  poll_interval_ms : Int
  max_poll_attempts : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn luma_image_value(
  model_id : LumaImageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  poll_interval_ms~ : Int,
  max_poll_attempts~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> LumaImageModel {
  {
    provider_name: "luma.image",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    poll_interval_ms,
    max_poll_attempts,
    http_transport,
  }
}

///|
fn LumaImageModel::request_headers(
  self : LumaImageModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="LUMAAI_API_KEY",
    description="LumaAI",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          ("Authorization", "Bearer \{api_key}"),
          ("Content-Type", "application/json"),
          ("accept", "application/json"),
        ]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the generation request body.
fn luma_image_request_body(
  model_id~ : String,
  prompt~ : String,
  aspect_ratio~ : String?,
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([
    ("prompt", Json::string(prompt)),
    ("model", Json::string(model_id)),
  ])
  if aspect_ratio is Some(value) {
    fields["aspect_ratio"] = Json::string(value)
  }
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
/// Extract the generation id from the submit response.
fn decode_luma_generation_id(value : Json) -> String raise {
  match value {
    { "id": String(id), .. } => id
    _ => fail("luma generation response missing id")
  }
}

///|
/// A completed generation yields the image URL under assets.image.
fn decode_luma_generation_status(value : Json) -> (String, String?) raise {
  match value {
    { "state": String(state), .. } => {
      let image_url = match value {
        { "assets": { "image": String(url), .. }, .. } => Some(url)
        _ => None
      }
      (state, image_url)
    }
    _ => fail("luma generation status response missing state")
  }
}

///|
pub impl @provider.ImageModelV4 for LumaImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for LumaImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for LumaImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for LumaImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.ImageModelV4 for LumaImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="This model does not support the `seed` option.",
      ),
    )
  }
  if options.size is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="size",
        details="This model does not support the `size` option. Use `aspectRatio` instead.",
      ),
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["luma"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  if options.files is Some(files) && files.length() > 0 {
    warnings.push(
      @provider.Warning::Other(
        message="Luma image references require absolute URLs in the `image_reference` provider option; inline files are ignored.",
      ),
    )
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let submit_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(
      self.base_url,
      "/dream-machine/v1/generations/image",
    ),
    headers=self.request_headers(extra=options.headers),
    body=luma_image_request_body(
      model_id=self.model_id,
      prompt=options.prompt.unwrap_or(""),
      aspect_ratio=options.aspect_ratio,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=luma_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let generation_id = @provider_utils.handle_json_response(
    submit_response, decode_luma_generation_id,
  )
  // Poll until the generation completes or fails.
  let mut image_url : String? = None
  let mut succeeded = false
  for attempt = 0; attempt < self.max_poll_attempts; attempt = attempt + 1 {
    @provider.check_cancellation(cancellation_token)
    @provider_utils.sleep_with_cancellation(
      self.poll_interval_ms,
      cancellation_token,
    )
    let poll_response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url=@provider_utils.append_path(
        self.base_url,
        "/dream-machine/v1/generations/\{generation_id}",
      ),
      headers=self.request_headers(extra=options.headers),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=luma_error_to_message,
      is_retryable_response=(_status_code, _error) => None,
      transport=self.http_transport,
    )
    let (state, url) = @provider_utils.handle_json_response(
      poll_response, decode_luma_generation_status,
    )
    if state == "completed" {
      image_url = url
      succeeded = true
      break
    }
    if state == "failed" {
      fail("luma image generation failed")
    }
  }
  guard succeeded else {
    fail(
      "luma image generation polling exhausted \{self.max_poll_attempts} attempts",
    )
  }
  let images = match image_url {
    Some(url) => [@provider.GeneratedImage::new(@provider.ImageData::Url(url))]
    None => []
  }
  @provider.ImageModelV4Result::new(
    images,
    warnings~,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      submit_response.value,
      self.provider_name,
    ),
    request=submit_response.request,
    response=@provider.merge_response_metadata(
      Some(submit_response.response),
      @provider.ResponseMetadata::new(
        model_id=self.model_id,
        created_at=request_created_at,
      ),
    ),
  )
}

///|
fn luma_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "failure_reason": String(message), .. } => Some(message)
    { "detail": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

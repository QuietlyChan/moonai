///|
/// The Black Forest Labs image model: submit to /{model}, then poll the
/// returned polling_url until status Ready; the sample URL carries the image.
struct BflImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  poll_interval_ms : Int
  poll_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn bfl_image_value(
  model_id : BflImageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  poll_interval_ms~ : Int,
  poll_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> BflImageModel {
  {
    provider_name: "bfl.image",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    poll_interval_ms,
    poll_timeout_ms,
    http_transport,
  }
}

///|
fn BflImageModel::request_headers(
  self : BflImageModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="BFL_API_KEY",
    description="Black Forest Labs",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([("x-key", api_key), ("Content-Type", "application/json")]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the submit request body.
fn bfl_image_request_body(
  prompt~ : String,
  n~ : Int,
  aspect_ratio~ : String?,
  seed~ : Int?,
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([("prompt", Json::string(prompt))])
  if n > 1 {
    fields["n"] = Json::number(n.to_double())
  }
  if aspect_ratio is Some(value) {
    fields["aspect_ratio"] = Json::string(value)
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
fn decode_bfl_submit(value : Json) -> String raise {
  match value {
    { "id": String(id), .. } => id
    _ => fail("bfl submit response missing id")
  }
}

///|
/// A Ready poll response carries the sample image URL.
fn decode_bfl_poll(value : Json) -> (String, String?) raise {
  match value {
    { "status": String(status), .. } => {
      let sample = match value {
        { "result": { "sample": String(url), .. }, .. } => Some(url)
        _ => None
      }
      (status, sample)
    }
    _ => fail("bfl poll response missing status")
  }
}

///|
pub impl @provider.ImageModelV4 for BflImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for BflImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for BflImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for BflImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.ImageModelV4 for BflImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["bfl"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  if options.mask is Some(_) {
    warnings.push(@provider.Warning::unsupported("mask"))
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let submit_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, self.model_id),
    headers=self.request_headers(extra=options.headers),
    body=bfl_image_request_body(
      prompt=options.prompt.unwrap_or(""),
      n=options.n,
      aspect_ratio=options.aspect_ratio,
      seed=options.seed,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=bfl_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let job_id = @provider_utils.handle_json_response(
    submit_response, decode_bfl_submit,
  )
  let poll_url = match submit_response.value {
    { "polling_url": String(url), .. } => url
    _ => "https://api.bfl.ai/v1/get_result?id=\{job_id}"
  }
  let poll_started_at = @env.now()
  let mut sample_url : String? = None
  let mut succeeded = false
  for ;; {
    @provider.check_cancellation(cancellation_token)
    @provider_utils.sleep_with_cancellation(
      self.poll_interval_ms,
      cancellation_token,
    )
    if @env.now() - poll_started_at > self.poll_timeout_ms.to_uint64() {
      fail("bfl image polling exceeded \{self.poll_timeout_ms}ms")
    }
    let poll_response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url=poll_url,
      headers=self.request_headers(extra=options.headers),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=bfl_error_to_message,
      is_retryable_response=(_status_code, _error) => None,
      transport=self.http_transport,
    )
    let (status, sample) = @provider_utils.handle_json_response(
      poll_response, decode_bfl_poll,
    )
    if status == "Ready" {
      sample_url = sample
      succeeded = true
      break
    }
    if status == "Error" || status == "Content Moderated" {
      fail("bfl image generation failed with status \{status}")
    }
  }
  guard succeeded else { fail("bfl image generation did not complete") }
  let images = match sample_url {
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
fn bfl_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "detail": String(message), .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

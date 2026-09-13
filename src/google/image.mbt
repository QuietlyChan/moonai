///|
/// The Google image model: generateContent with IMAGE response modality
/// (Gemini native image generation, e.g. `gemini-2.5-flash-image`).
struct GoogleImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn google_image_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GoogleImageModel {
  {
    provider_name: "google.image",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn GoogleImageModel::image_headers(
  self : GoogleImageModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          (
            "x-goog-api-key",
            @provider_utils.load_api_key(
              self.api_key,
              environment_variable_name="GOOGLE_GENERATIVE_AI_API_KEY",
              description="Google Gemini",
            ),
          ),
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
/// Build the generateContent body with the IMAGE response modality.
fn google_image_request_body(
  prompt~ : String,
  n~ : Int,
  size~ : String?,
  aspect_ratio~ : String?,
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([
    (
      "contents",
      Json::object({
        "role": "user",
        "parts": Json::array([{ "text": prompt }]),
      }),
    ),
  ])
  let generation_config : Map[String, Json] = Map([])
  generation_config["responseModalities"] = Json::array([
    Json::string("TEXT"),
    Json::string("IMAGE"),
  ])
  if n > 1 {
    generation_config["candidateCount"] = Json::number(n.to_double())
  }
  match aspect_ratio {
    Some(value) => generation_config["imageAspectRatio"] = Json::string(value)
    None => ()
  }
  match size {
    Some(value) => generation_config["imageSize"] = Json::string(value)
    None => ()
  }
  for entry in provider_options.iter2() {
    generation_config[entry.0] = entry.1
  }
  fields["generationConfig"] = Json::object(generation_config)
  Json::object(fields)
}

///|
/// Collect Base64 image parts (inlineData with image/* media type).
fn decode_google_image_parts(
  value : Json,
) -> Array[@provider.GeneratedImage] raise {
  let images : Array[@provider.GeneratedImage] = []
  match value {
    { "candidates": Array(candidates), .. } =>
      if candidates.length() > 0 {
        match candidates[0] {
          { "content": { "parts": Array(parts), .. }, .. } =>
            for part in parts {
              match part {
                {
                  "inlineData": {
                    "mimeType": String(_),
                    "data": String(data),
                    ..
                  },
                  ..
                } =>
                  images.push(
                    @provider.GeneratedImage::new(
                      @provider.ImageData::Base64(data),
                    ),
                  )
                _ => ()
              }
            }
          _ => ()
        }
      }
    _ => ()
  }
  if images.length() == 0 {
    fail("google image response contained no image parts")
  }
  images
}

///|
pub impl @provider.ImageModelV4 for GoogleImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for GoogleImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for GoogleImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for GoogleImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  None
}

///|
pub impl @provider.ImageModelV4 for GoogleImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  if options.mask is Some(_) {
    warnings.push(@provider.Warning::unsupported("mask"))
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["google"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url="\{self.base_url}/\{get_model_path(self.model_id)}:generateContent",
    headers=self.image_headers(extra=options.headers),
    body=google_image_request_body(
      prompt=options.prompt.unwrap_or(""),
      n=options.n,
      size=options.size,
      aspect_ratio=options.aspect_ratio,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=google_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let images = @provider_utils.handle_json_response(
    response, decode_google_image_parts,
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

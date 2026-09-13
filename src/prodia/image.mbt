///|
/// The Prodia image model: POST /job?price=true (JSON job body) returns a
/// multipart response carrying the job result and the PNG bytes.
struct ProdiaImageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn prodia_image_value(
  model_id : ProdiaImageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> ProdiaImageModel {
  {
    provider_name: "prodia",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Build the image job config. `size` maps to width/height unless the
/// `prodia` namespace supplies them directly; malformed sizes warn and are
/// dropped.
fn prodia_image_job_config(
  options : @provider.ImageModelV4CallOptions,
  resolution_values : Map[String, Json],
  warnings : Array[@provider.Warning],
) -> Map[String, Json] {
  let config : Map[String, Json] = Map([])
  if options.prompt is Some(value) {
    config["prompt"] = Json::string(value)
  }
  let mut width : Json? = None
  let mut height : Json? = None
  if resolution_values.get("width") is Some(value) {
    width = Some(value)
  }
  if resolution_values.get("height") is Some(value) {
    height = Some(value)
  }
  if (width is None || height is None) && options.size is Some(value) {
    let parts = value.split("x").to_array()
    let parsed : Array[Json] = []
    let mut valid = parts.length() == 2
    if valid {
      for part in parts {
        match part.to_owned().trim().to_owned() {
          text =>
            try {
              let number = @string.parse_int64(text, base=10)
              parsed.push(Json::number(number.to_double()))
            } catch {
              _ => {
                valid = false
                break
              }
            }
        }
      }
    }
    if valid {
      if width is None && parsed.length() == 2 {
        width = Some(parsed[0])
      }
      if height is None && parsed.length() == 2 {
        height = Some(parsed[1])
      }
    } else {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="size",
          details="Invalid size format: \{value}. Expected format: WIDTHxHEIGHT (e.g., 1024x1024)",
        ),
      )
    }
  }
  if width is Some(value) {
    config["width"] = value
  }
  if height is Some(value) {
    config["height"] = value
  }
  if options.seed is Some(value) {
    config["seed"] = Json::number(value.to_double())
  }
  if resolution_values.get("steps") is Some(value) {
    config["steps"] = value
  }
  if resolution_values.get("style_preset") is Some(value) {
    config["style_preset"] = value
  } else if resolution_values.get("stylePreset") is Some(value) {
    config["style_preset"] = value
  }
  if resolution_values.get("negative_prompt") is Some(value) {
    config["negative_prompt"] = value
  }
  if resolution_values.get("guidance_scale") is Some(value) {
    config["guidance_scale"] = value
  }
  config
}

///|
pub impl @provider.ImageModelV4 for ProdiaImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for ProdiaImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for ProdiaImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for ProdiaImageModel with fn max_images_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.ImageModelV4 for ProdiaImageModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["prodia"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let config = prodia_image_job_config(options, resolution.values, warnings)
  let job_fields : Map[String, Json] = Map([
    ("type", Json::string(self.model_id)),
    ("config", Json::object(config)),
  ])
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json_binary(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/job?price=true"),
    headers=prodia_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
      content_type="application/json",
      accept="multipart/form-data; image/png",
    ),
    body=Json::object(job_fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=prodia_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let content_type = response.response.headers.get("content-type").unwrap_or("")
  let parts = @provider_utils.parse_multipart_response(
    content_type~,
    data=response.value,
  )
  let job = decode_prodia_job_part(parts)
  let image_part = @provider_utils.multipart_response_part_by_name(
    parts,
    name="output",
  )
  let image_part = match image_part {
    Some(part) => Some(part)
    None =>
      @provider_utils.multipart_response_part_by_content_type_prefix(
        parts,
        prefix="image/",
      )
  }
  guard image_part is Some(part) else {
    fail("prodia multipart response missing output image")
  }
  let images = [
    @provider.GeneratedImage::new(
      @provider.ImageData::Base64(@base64.encode(part.body, padding=true)),
    ),
  ]
  @provider.ImageModelV4Result::new(
    images,
    warnings~,
    provider_metadata=prodia_job_metadata(job),
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

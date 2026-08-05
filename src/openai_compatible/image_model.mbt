///|
/// An image model using the OpenAI image generation wire protocol.
pub struct OpenAICompatibleImageModel {
  priv provider_name : String
  priv api_key : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv max_images : Int
  priv include_response_format : Bool
  priv error_structure : OpenAICompatibleErrorStructure
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct an OpenAI-compatible image model directly.
pub fn openai_compatible_image(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  max_images_per_call? : Int = 10,
  include_response_format? : Bool = false,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
) -> OpenAICompatibleImageModel {
  {
    provider_name: "\{provider_name}.image",
    api_key,
    api_key_environment_variable,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    headers: @provider_utils.copy_headers(headers),
    query_params: @provider_utils.copy_headers(query_params),
    max_images: max_images_per_call,
    include_response_format,
    error_structure,
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
fn OpenAICompatibleImageModel::generations_url(
  self : OpenAICompatibleImageModel,
) -> String {
  @provider_utils.append_query(
    @provider_utils.append_path(self.base_url, "/images/generations"),
    self.query_params,
  )
}

///|
fn OpenAICompatibleImageModel::edits_url(
  self : OpenAICompatibleImageModel,
) -> String {
  @provider_utils.append_query(
    @provider_utils.append_path(self.base_url, "/images/edits"),
    self.query_params,
  )
}

///|
fn image_form_value(value : Json) -> String? {
  match value {
    Null => None
    String(value) => Some(value)
    True => Some("true")
    False => Some("false")
    Number(value, ..) => Some(value.to_string())
    other => Some(other.stringify())
  }
}

///|
async fn OpenAICompatibleImageModel::edit_form_data(
  self : OpenAICompatibleImageModel,
  options : @provider.ImageCallOptions,
  provider_options : Map[String, Json],
) -> @provider_utils.MultipartFormData {
  let cancellation_token = options.cancellation_token
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::text(name="model", value=self.model_id),
    @provider_utils.MultipartField::text(name="prompt", value=options.prompt),
    @provider_utils.MultipartField::text(name="n", value=options.n.to_string()),
  ]
  if options.size is Some(value) && provider_options.get("size") is None {
    fields.push(@provider_utils.MultipartField::text(name="size", value~))
  }
  for entry in provider_options.iter2() {
    let (key, value) = entry
    if image_form_value(value) is Some(text) {
      fields.push(
        @provider_utils.MultipartField::text(
          name=image_option_wire_key(key),
          value=text,
        ),
      )
    }
  }
  let image_field = if options.files.length() == 1 {
    "image"
  } else {
    "image[]"
  }
  for file in options.files {
    let resolved = @provider_utils.resolve_image_file(
      file,
      provider_name=self.provider_name,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      transport=self.http_transport,
    )
    fields.push(
      @provider_utils.MultipartField::file(
        name=image_field,
        filename=resolved.filename,
        media_type=resolved.media_type,
        data=resolved.data,
      ),
    )
  }
  if options.mask is Some(mask) {
    let resolved = @provider_utils.resolve_image_file(
      mask,
      provider_name=self.provider_name,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
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
  @provider_utils.encode_multipart_form_data(fields)
}

///|
fn OpenAICompatibleImageModel::request_headers(
  self : OpenAICompatibleImageModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  let api_key = match self.api_key_environment_variable {
    Some(environment_variable_name) =>
      Some(
        @provider_utils.load_api_key(
          self.api_key,
          environment_variable_name~,
          description=self.provider_name,
        ),
      )
    None if self.api_key != "" => Some(self.api_key)
    None => None
  }
  match api_key {
    Some(value) => headers["Authorization"] = "Bearer \{value}"
    None => ()
  }
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    [openai_compatible_user_agent_suffix(self.provider_name)],
  )
}

///|
pub impl @provider.ImageWireModel for OpenAICompatibleImageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageWireModel for OpenAICompatibleImageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.ImageWireModel for OpenAICompatibleImageModel with fn max_images_per_call(
  self,
) -> Int {
  self.max_images
}

///|
pub impl @provider.ImageWireModel for OpenAICompatibleImageModel with fn generate(
  self,
  options,
) {
  self.generate_images(options)
}

///|
async fn OpenAICompatibleImageModel::generate_images(
  self : OpenAICompatibleImageModel,
  options : @provider.ImageCallOptions,
) -> @provider.ImageResponse {
  let option_resolution = resolve_compatible_options(
    options.provider_options,
    self.provider_name,
    image_reserved_fields(),
  )
  let warnings = compatible_image_request_warnings(options, option_resolution)
  let request_headers = @provider_utils.merge_headers(
    self.request_headers(),
    options.headers,
  )
  let cancellation_token = options.cancellation_token
  guard options.mask is None || options.files.length() > 0 else {
    fail("OpenAI-compatible image edits require at least one input file")
  }
  let response = if options.files.length() > 0 {
    let form_data = self.edit_form_data(options, option_resolution.values)
    @provider_utils.post_multipart(
      provider_name=self.provider_name,
      url=self.edits_url(),
      headers=request_headers,
      form_data~,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=json => self.error_structure.message(json),
      is_retryable_response=(status_code, error) => {
        self.error_structure.retryable(status_code, error)
      },
      transport=self.http_transport,
    )
  } else {
    @provider_utils.post_json(
      provider_name=self.provider_name,
      url=self.generations_url(),
      headers=request_headers,
      body=encode_image_request(
        self.model_id,
        options,
        include_response_format=self.include_response_format,
        provider_name=self.provider_name,
      ),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=json => self.error_structure.message(json),
      is_retryable_response=(status_code, error) => {
        self.error_structure.retryable(status_code, error)
      },
      transport=self.http_transport,
    )
  }
  let decoded = decode_image_response(
    response.value,
    error_structure=self.error_structure,
  )
  decoded
  .with_diagnostics(
    None,
    None,
    @provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    warnings,
  )
  .with_transport(response.request, response.response)
}

///|
/// Convert V4 options at the OpenAI-compatible protocol boundary.
fn compatible_v4_image_options(
  options : @provider.ImageModelV4CallOptions,
) -> @provider.ImageCallOptions {
  let prompt = options.prompt.unwrap_or("")
  let files : Array[@provider.ImageFile] = match options.files {
    Some(values) => [ for file in values => file.to_image_file() ]
    None => []
  }
  let mask = match options.mask {
    Some(value) => Some(value.to_image_file(filename="mask"))
    None => None
  }
  @provider.ImageCallOptions::new(
    prompt,
    n=options.n,
    size?=options.size,
    aspect_ratio?=options.aspect_ratio,
    seed?=options.seed,
    files~,
    mask?,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
pub impl @provider.ImageModelV4 for OpenAICompatibleImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for OpenAICompatibleImageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for OpenAICompatibleImageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for OpenAICompatibleImageModel with fn max_images_per_call(
  self,
) -> Int? {
  Some(self.max_images)
}

///|
pub impl @provider.ImageModelV4 for OpenAICompatibleImageModel with fn do_generate(
  self,
  options,
) {
  @provider.ImageModelV4Result::from_image_response(
    self.generate_images(compatible_v4_image_options(options)),
  )
}

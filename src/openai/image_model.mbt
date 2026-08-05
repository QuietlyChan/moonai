///|
/// Official OpenAI image generation and editing model.
pub struct OpenAIImageModel {
  priv provider_name : String
  priv base_url : String
  priv model_id : String
  priv api_key : String
  priv headers : Map[String, String]
  priv max_images : Int
  priv include_response_format : Bool
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn openai_image_model(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  max_images_per_call~ : Int,
  include_response_format~ : Bool,
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAIImageModel {
  {
    provider_name: "\{provider_name}.image",
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    max_images: max_images_per_call,
    include_response_format,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn OpenAIImageModel::generations_url(self : OpenAIImageModel) -> String {
  @provider_utils.append_path(self.base_url, "/images/generations")
}

///|
fn OpenAIImageModel::edits_url(self : OpenAIImageModel) -> String {
  @provider_utils.append_path(self.base_url, "/images/edits")
}

///|
fn OpenAIImageModel::request_headers(
  self : OpenAIImageModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/openai/\{VERSION}"],
  )
}

///|
fn append_openai_image_string(
  fields : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  if value is Some(item) {
    fields[key] = Json::string(item)
  }
}

///|
fn append_openai_image_int(
  fields : Map[String, Json],
  key : String,
  value : Int?,
) -> Unit {
  if value is Some(item) {
    fields[key] = Json::number(item.to_double())
  }
}

///|
fn openai_image_generation_body(
  model_id : String,
  call_options : @provider.ImageCallOptions,
  provider_options : OpenAIImageOptions,
  include_response_format : Bool,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("model", Json::string(model_id)),
    ("prompt", Json::string(call_options.prompt)),
    ("n", Json::number(call_options.n.to_double())),
  ])
  append_openai_image_string(fields, "size", call_options.size)
  append_openai_image_string(fields, "quality", provider_options.quality)
  append_openai_image_string(fields, "style", provider_options.style)
  append_openai_image_string(fields, "background", provider_options.background)
  append_openai_image_string(fields, "moderation", provider_options.moderation)
  append_openai_image_string(
    fields,
    "output_format",
    provider_options.output_format,
  )
  append_openai_image_int(
    fields,
    "output_compression",
    provider_options.output_compression,
  )
  append_openai_image_string(fields, "user", provider_options.user)
  if include_response_format {
    fields["response_format"] = Json::string("b64_json")
  }
  Json::object(fields)
}

///|
fn append_openai_form_text(
  fields : Array[@provider_utils.MultipartField],
  name : String,
  value : String?,
) -> Unit {
  if value is Some(item) {
    fields.push(@provider_utils.MultipartField::text(name~, value=item))
  }
}

///|
fn append_openai_form_int(
  fields : Array[@provider_utils.MultipartField],
  name : String,
  value : Int?,
) -> Unit {
  if value is Some(item) {
    fields.push(
      @provider_utils.MultipartField::text(name~, value=item.to_string()),
    )
  }
}

///|
async fn OpenAIImageModel::edit_form_data(
  self : OpenAIImageModel,
  call_options : @provider.ImageCallOptions,
  provider_options : OpenAIImageOptions,
) -> @provider_utils.MultipartFormData {
  let cancellation_token = call_options.cancellation_token
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::text(name="model", value=self.model_id),
    @provider_utils.MultipartField::text(
      name="prompt",
      value=call_options.prompt,
    ),
    @provider_utils.MultipartField::text(
      name="n",
      value=call_options.n.to_string(),
    ),
  ]
  append_openai_form_text(fields, "size", call_options.size)
  append_openai_form_text(fields, "quality", provider_options.quality)
  append_openai_form_text(fields, "background", provider_options.background)
  append_openai_form_text(
    fields,
    "output_format",
    provider_options.output_format,
  )
  append_openai_form_int(
    fields,
    "output_compression",
    provider_options.output_compression,
  )
  append_openai_form_text(
    fields,
    "input_fidelity",
    provider_options.input_fidelity,
  )
  append_openai_form_text(fields, "user", provider_options.user)
  let image_field = if call_options.files.length() == 1 {
    "image"
  } else {
    "image[]"
  }
  for file in call_options.files {
    let resolved = @provider_utils.resolve_image_file(
      file,
      provider_name=self.provider_name,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=call_options.retry_policy,
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
  if call_options.mask is Some(mask) {
    let resolved = @provider_utils.resolve_image_file(
      mask,
      provider_name=self.provider_name,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=call_options.retry_policy,
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
fn openai_image_warnings(
  call_options : @provider.ImageCallOptions,
  parsed : ParsedOpenAIImageOptions,
  editing : Bool,
) -> Array[@provider.Warning] {
  let warnings = parsed.warnings.copy()
  if call_options.aspect_ratio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="OpenAI image models use size instead of aspectRatio.",
      ),
    )
  }
  if call_options.seed is Some(_) {
    warnings.push(@provider.Warning::unsupported("seed"))
  }
  if editing {
    if parsed.options.style is Some(_) {
      warnings.push(
        @provider.Warning::unsupported("providerOptions.openai.style"),
      )
    }
    if parsed.options.moderation is Some(_) {
      warnings.push(
        @provider.Warning::unsupported("providerOptions.openai.moderation"),
      )
    }
  } else if parsed.options.input_fidelity is Some(_) {
    warnings.push(
      @provider.Warning::unsupported("providerOptions.openai.inputFidelity"),
    )
  }
  warnings
}

///|
fn openai_image_usage(json : Json) -> @provider.Usage {
  match json {
    { "usage": usage, .. } =>
      {
        input_tokens: @provider_utils.json_int_field(usage, "input_tokens"),
        output_tokens: @provider_utils.json_int_field(usage, "output_tokens"),
        total_tokens: @provider_utils.json_int_field(usage, "total_tokens"),
        reasoning_tokens: 0,
        cached_input_tokens: 0,
        cache_write_input_tokens: 0,
      }
    _ => @provider.Usage::zero()
  }
}

///|
fn openai_generated_image(json : Json) -> @provider.GeneratedImage raise {
  let data = match json {
    { "b64_json": String(value), .. } => @provider.ImageData::Base64(value)
    { "url": String(value), .. } => @provider.ImageData::Url(value)
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI image item has no b64_json or url",
        data=json,
      )
  }
  let revised_prompt = match json {
    { "revised_prompt": String(value), .. } => Some(value)
    _ => None
  }
  @provider.GeneratedImage::new(data, revised_prompt?)
}

///|
fn openai_distributed_image_token_detail(
  json : Json,
  field : String,
  index : Int,
  total : Int,
) -> Int? {
  guard total > 0 else { return None }
  let value = match json {
    { "usage": Object(usage), .. } =>
      match usage.get("input_tokens_details") {
        Some(details) => @provider_utils.json_int_field_opt(details, field)
        None => None
      }
    _ => None
  }
  match value {
    Some(tokens) => {
      let base = tokens / total
      Some(if index == total - 1 { tokens - base * (total - 1) } else { base })
    }
    None => None
  }
}

///|
fn openai_image_metadata(json : Json) -> Map[String, Json] {
  let image_metadata : Array[Json] = []
  match json {
    { "data": Array(items), .. } =>
      for index, item in items {
        let fields : Map[String, Json] = Map([])
        match item {
          { "revised_prompt": String(value), .. } =>
            fields["revisedPrompt"] = Json::string(value)
          _ => ()
        }
        match json {
          Object(response) =>
            for
              key in [
                "created", "size", "quality", "background", "output_format",
              ] {
              if response.get(key) is Some(value) {
                fields[if key == "output_format" {
                  "outputFormat"
                } else {
                  key
                }] = value
              }
            }
          _ => ()
        }
        if openai_distributed_image_token_detail(
            json,
            "image_tokens",
            index,
            items.length(),
          )
          is Some(value) {
          fields["imageTokens"] = Json::number(value.to_double())
        }
        if openai_distributed_image_token_detail(
            json,
            "text_tokens",
            index,
            items.length(),
          )
          is Some(value) {
          fields["textTokens"] = Json::number(value.to_double())
        }
        image_metadata.push(Json::object(fields))
      }
    _ => ()
  }
  Map([("openai", ({ "images": image_metadata } : Json))])
}

///|
fn decode_openai_image_response(json : Json) -> @provider.ImageResponse raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI image request failed: \{message}",
      data=json,
    )
  }
  let items = match json {
    { "data": Array(values), .. } => values
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI image response has no data",
        data=json,
      )
  }
  let images : Array[@provider.GeneratedImage] = []
  for item in items {
    images.push(openai_generated_image(item))
  }
  @provider.ImageResponse::new(images, openai_image_usage(json))
}

///|
pub impl @provider.ImageWireModel for OpenAIImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageWireModel for OpenAIImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageWireModel for OpenAIImageModel with fn max_images_per_call(
  self,
) -> Int {
  self.max_images
}

///|
pub impl @provider.ImageWireModel for OpenAIImageModel with fn generate(
  self,
  options,
) {
  self.generate_images(options)
}

///|
async fn OpenAIImageModel::generate_images(
  self : OpenAIImageModel,
  call_options : @provider.ImageCallOptions,
) -> @provider.ImageResponse {
  let parsed = parse_openai_image_options(call_options, self.provider_name)
  let editing = call_options.files.length() > 0
  guard call_options.mask is None || editing else {
    fail("OpenAI image edits require at least one input file")
  }
  let warnings = openai_image_warnings(call_options, parsed, editing)
  let headers = @provider_utils.merge_headers(
    self.request_headers(),
    call_options.headers,
  )
  let cancellation_token = call_options.cancellation_token
  let response = if editing {
    let form_data = self.edit_form_data(call_options, parsed.options)
    @provider_utils.post_multipart(
      provider_name=self.provider_name,
      url=self.edits_url(),
      headers~,
      form_data~,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=call_options.retry_policy,
      cancellation_token?,
      error_to_message=openai_error_message,
      transport=self.http_transport,
    )
  } else {
    @provider_utils.post_json(
      provider_name=self.provider_name,
      url=self.generations_url(),
      headers~,
      body=openai_image_generation_body(
        self.model_id,
        call_options,
        parsed.options,
        self.include_response_format,
      ),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=call_options.retry_policy,
      cancellation_token?,
      error_to_message=openai_error_message,
      transport=self.http_transport,
    )
  }
  decode_openai_image_response(response.value)
  .with_diagnostics(None, None, openai_image_metadata(response.value), warnings)
  .with_transport(response.request, response.response)
}

///|
/// Convert V4 image options at the OpenAI protocol boundary.
fn openai_v4_image_options(
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
pub impl @provider.ImageModelV4 for OpenAIImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for OpenAIImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for OpenAIImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for OpenAIImageModel with fn max_images_per_call(
  self,
) -> Int? {
  Some(self.max_images)
}

///|
pub impl @provider.ImageModelV4 for OpenAIImageModel with fn do_generate(
  self,
  options,
) {
  @provider.ImageModelV4Result::from_image_response(
    self.generate_images(openai_v4_image_options(options)),
  )
}

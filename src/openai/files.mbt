///|
/// Official OpenAI Files API implementation.
pub struct OpenAIFiles {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Typed provider options for OpenAI Files uploads.
pub(all) struct OpenAIFilesOptions {
  purpose : String?
  expires_after : Double?
} derive(Debug, Eq)

///|
/// Construct OpenAI Files upload options.
pub fn OpenAIFilesOptions::new(
  purpose? : String,
  expires_after? : Double,
) -> OpenAIFilesOptions {
  { purpose, expires_after }
}

///|
/// Convert typed Files options into the OpenAI provider namespace.
pub fn OpenAIFilesOptions::to_provider_options(
  self : OpenAIFilesOptions,
  provider_name? : String = "openai",
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.purpose is Some(value) {
    values["purpose"] = Json::string(value)
  }
  if self.expires_after is Some(value) {
    values["expiresAfter"] = Json::number(value)
  }
  Map([(provider_name, Json::object(values))])
}

///|
priv struct ParsedOpenAIFilesOptions {
  options : OpenAIFilesOptions
  warnings : Array[@provider.Warning]
}

///|
fn openai_files(
  provider_name~ : String,
  base_url~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAIFiles {
  {
    provider_name: "\{provider_name}.files",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn OpenAIFiles::url(self : OpenAIFiles) -> String {
  @provider_utils.append_path(self.base_url, "/files")
}

///|
fn OpenAIFiles::request_headers(
  self : OpenAIFiles,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/openai/\{VERSION}"],
  )
}

///|
fn parse_openai_files_options(
  call_options : @provider.FileUploadOptions,
  provider_name : String,
) -> ParsedOpenAIFilesOptions {
  let resolution = @provider_utils.resolve_provider_options(
    call_options.provider_options,
    provider_name~,
    aliases=["openai"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(
    resolution,
    path="providerOptions.openai",
  )
  let purpose = reader.take_string("purpose")
  let expires_after = reader.take_double("expiresAfter", aliases=[
    "expires_after",
  ])
  { options: { purpose, expires_after }, warnings: reader.diagnostics() }
}

///|
fn OpenAIFiles::form_data(
  _self : OpenAIFiles,
  call_options : @provider.FileUploadOptions,
  parsed : ParsedOpenAIFilesOptions,
) -> @provider_utils.MultipartFormData raise {
  let filename = call_options.filename.unwrap_or("blob")
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::file(
      name="file",
      filename~,
      media_type=call_options.media_type,
      data=@provider_utils.resolve_upload_file_data(call_options.data),
    ),
    @provider_utils.MultipartField::text(
      name="purpose",
      value=parsed.options.purpose.unwrap_or("assistants"),
    ),
  ]
  if parsed.options.expires_after is Some(seconds) {
    fields.push(
      @provider_utils.MultipartField::text(
        name="expires_after[anchor]",
        value="created_at",
      ),
    )
    fields.push(
      @provider_utils.MultipartField::text(
        name="expires_after[seconds]",
        value=seconds.to_string(),
      ),
    )
  }
  @provider_utils.encode_multipart_form_data(fields)
}

///|
fn openai_files_provider_metadata(json : Json) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  match json {
    { "filename": String(value), .. } =>
      fields["filename"] = Json::string(value)
    _ => ()
  }
  match json {
    { "purpose": String(value), .. } => fields["purpose"] = Json::string(value)
    _ => ()
  }
  match json {
    { "bytes": Number(value, ..), .. } => fields["bytes"] = Json::number(value)
    _ => ()
  }
  match json {
    { "created_at": Number(value, ..), .. } =>
      fields["createdAt"] = Json::number(value)
    _ => ()
  }
  match json {
    { "status": String(value), .. } => fields["status"] = Json::string(value)
    _ => ()
  }
  match json {
    { "expires_at": Number(value, ..), .. } =>
      fields["expiresAt"] = Json::number(value)
    _ => ()
  }
  Map([("openai", Json::object(fields))])
}

///|
fn decode_openai_file_upload(
  json : Json,
  call_options : @provider.FileUploadOptions,
  parsed : ParsedOpenAIFilesOptions,
) -> @provider.FileUploadResult raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI Files request failed: \{message}",
      data=json,
    )
  }
  let id = match json {
    { "id": String(value), .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Files response has no file id",
        data=json,
      )
  }
  let filename = match json {
    { "filename": String(value), .. } => Some(value)
    _ => call_options.filename
  }
  @provider.FileUploadResult::new(
    provider_reference=@provider.ProviderReference::single(
      provider="openai",
      id~,
    ),
    media_type=call_options.media_type,
    filename?,
    provider_metadata=openai_files_provider_metadata(json),
    warnings=parsed.warnings,
  )
}

///|
async fn OpenAIFiles::upload(
  self : OpenAIFiles,
  call_options : @provider.FileUploadOptions,
) -> @provider.FileUploadResult {
  let parsed = parse_openai_files_options(call_options, self.provider_name)
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=self.url(),
    headers=self.request_headers(),
    form_data=self.form_data(call_options, parsed),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  decode_openai_file_upload(response.value, call_options, parsed)
}

///|
pub impl @provider.Files for OpenAIFiles with fn provider(self : OpenAIFiles) -> String {
  self.provider_name
}

///|
pub impl @provider.Files for OpenAIFiles with fn upload_file(
  self : OpenAIFiles,
  call_options : @provider.FileUploadOptions,
) -> @provider.FileUploadResult {
  self.upload(call_options)
}

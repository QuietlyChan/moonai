///|
/// Anthropic Files API implementation.
pub struct AnthropicFiles {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv auth_token : String
  priv api_key_environment_variable : String?
  priv anthropic_version : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct an Anthropic Files API client directly.
pub fn anthropic_files(
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "",
  provider_name? : String = "anthropic.files",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
) -> AnthropicFiles raise {
  guard api_key == "" || auth_token == "" else {
    raise @provider.InvalidArgumentError(
      argument="api_key/auth_token",
      message="Both api_key and auth_token were provided. Please use only one authentication method.",
    )
  }
  {
    provider_name,
    base_url: resolve_anthropic_base_url(base_url),
    api_key,
    auth_token,
    api_key_environment_variable,
    anthropic_version,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Select the Files API from an Anthropic provider factory.
pub fn AnthropicProvider::files(
  self : AnthropicProvider,
) -> AnthropicFiles raise {
  let api_key_environment_variable = self.api_key_environment_variable
  anthropic_files(
    api_key=self.api_key,
    auth_token=self.auth_token,
    base_url=self.base_url,
    provider_name=self.provider_name,
    headers=self.headers,
    anthropic_version=self.anthropic_version,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    api_key_environment_variable?,
  )
}

///|
fn AnthropicFiles::files_url(self : AnthropicFiles) -> String {
  @provider_utils.append_path(self.base_url, "/files")
}

///|
fn AnthropicFiles::request_headers(
  self : AnthropicFiles,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Accept-Encoding"] = "identity"
  headers["anthropic-version"] = self.anthropic_version
  headers["anthropic-beta"] = "files-api-2025-04-14"
  for
    entry in anthropic_authentication_headers(
      self.api_key,
      self.auth_token,
      self.api_key_environment_variable,
    ).iter2() {
    let (key, value) = entry
    headers[key] = value
  }
  let merged = @provider_utils.merge_headers(headers, self.headers)
  merged["anthropic-beta"] = "files-api-2025-04-14"
  @provider_utils.with_user_agent_suffix(merged, ["moonai/anthropic/\{VERSION}"])
}

///|
fn anthropic_file_metadata(json : Json) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  match json {
    { "filename": String(value), .. } =>
      fields["filename"] = Json::string(value)
    _ => ()
  }
  match json {
    { "mime_type": String(value), .. } =>
      fields["mimeType"] = Json::string(value)
    _ => ()
  }
  match json {
    { "size_bytes": Number(value, ..), .. } =>
      fields["sizeBytes"] = Json::number(value)
    _ => ()
  }
  match json {
    { "created_at": String(value), .. } =>
      fields["createdAt"] = Json::string(value)
    _ => ()
  }
  match json {
    { "downloadable": true, .. } => fields["downloadable"] = Json::boolean(true)
    { "downloadable": false, .. } =>
      fields["downloadable"] = Json::boolean(false)
    _ => ()
  }
  Map([("anthropic", Json::object(fields))])
}

///|
fn decode_anthropic_file_upload(
  json : Json,
  options : @provider.FileUploadOptions,
) -> @provider.FileUploadResult raise {
  match anthropic_error_message(json) {
    Some(message) =>
      raise @provider.InvalidResponseDataError(
        message="Anthropic Files request failed: \{message}",
        data=json,
      )
    None => ()
  }
  let id = match json {
    { "id": String(value), .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Anthropic Files response has no file id",
        data=json,
      )
  }
  let filename = match json {
    { "filename": String(value), .. } => Some(value)
    _ => options.filename
  }
  let media_type = match json {
    { "mime_type": String(value), .. } => Some(value)
    _ => Some(options.media_type)
  }
  @provider.FileUploadResult::new(
    provider_reference=@provider.ProviderReference::single(
      provider="anthropic",
      id~,
    ),
    media_type?,
    filename?,
    provider_metadata=anthropic_file_metadata(json),
  )
}

///|
async fn AnthropicFiles::upload(
  self : AnthropicFiles,
  options : @provider.FileUploadOptions,
) -> @provider.FileUploadResult {
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::file(
      name="file",
      filename=options.filename.unwrap_or("blob"),
      media_type=options.media_type,
      data=@provider_utils.resolve_upload_file_data(options.data),
    ),
  ]
  let form_data = @provider_utils.encode_multipart_form_data(fields)
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=self.files_url(),
    headers=self.request_headers(),
    form_data~,
    timeout_ms=self.idle_timeout_ms,
    error_to_message=anthropic_error_message,
    transport=self.http_transport,
  )
  decode_anthropic_file_upload(response.value, options)
}

///|
pub impl @provider.Files for AnthropicFiles with fn provider(
  self : AnthropicFiles,
) -> String {
  self.provider_name
}

///|
pub impl @provider.Files for AnthropicFiles with fn upload_file(
  self : AnthropicFiles,
  options : @provider.FileUploadOptions,
) -> @provider.FileUploadResult {
  self.upload(options)
}

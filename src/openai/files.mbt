///|
/// Official OpenAI Files API implementation.
priv struct OpenAIFiles {
  provider_name : String
  base_url : String
  api_key : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
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
  { purpose, expires_after, }
}

///|
/// Convert typed FilesV4 options into the OpenAI provider namespace.
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
  call_options : @provider.FilesV4UploadFileCallOptions,
  _provider_name : String,
) -> ParsedOpenAIFilesOptions {
  let resolution = resolve_official_openai_provider_options(
    call_options.provider_options,
  )
  let reader = @provider_utils.ProviderOptionsReader::new(
    resolution,
    path="providerOptions.openai",
  )
  let purpose = reader.take_string("purpose")
  let expires_after = reader.take_double("expiresAfter", aliases=[
    "expires_after",
  ])
  { options: { purpose, expires_after, }, warnings: reader.diagnostics(), }
}

///|
fn OpenAIFiles::form_data(
  _self : OpenAIFiles,
  call_options : @provider.FilesV4UploadFileCallOptions,
  parsed : ParsedOpenAIFilesOptions,
) -> @provider_utils.MultipartFormData raise {
  let filename = call_options.filename.unwrap_or("blob")
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::file(
      name="file",
      filename~,
      media_type=call_options.media_type,
      data=@provider_utils.convert_inline_file_data_to_bytes(call_options.data),
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
  call_options : @provider.FilesV4UploadFileCallOptions,
  parsed : ParsedOpenAIFilesOptions,
) -> @provider.FilesV4UploadFileResult raise {
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
  @provider.FilesV4UploadFileResult::new(
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
  call_options : @provider.FilesV4UploadFileCallOptions,
) -> @provider.FilesV4UploadFileResult {
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
  @provider_utils.handle_json_response(response, value => {
    decode_openai_file_upload(value, call_options, parsed)
  })
}

///|
impl @provider.FilesV4 for OpenAIFiles with fn specification_version(
  _self : OpenAIFiles,
) -> String {
  "v4"
}

///|
impl @provider.FilesV4 for OpenAIFiles with fn provider(self : OpenAIFiles) -> String {
  self.provider_name
}

///|
impl @provider.FilesV4 for OpenAIFiles with fn upload_file(
  self : OpenAIFiles,
  call_options : @provider.FilesV4UploadFileCallOptions,
) -> @provider.FilesV4UploadFileResult {
  self.upload(call_options)
}

///|
fn OpenAIFiles::file_url(self : OpenAIFiles, file_id : String) -> String {
  @provider_utils.append_path(
    self.url(),
    "/\{@provider_utils.encode_path_segment(file_id)}",
  )
}

///|
fn openai_files_lifecycle_metadata(
  json : Json,
  file_id : String,
) -> Map[String, Json] {
  match json {
    Object(_) => openai_files_provider_metadata(json)
    _ => Map([("openai", Json::object(Map([("id", Json::string(file_id))])))])
  }
}

///|
fn openai_files_lifecycle_fields(json : Json) -> (String?, Int?, Int?, Int?) {
  let filename = match json {
    { "filename": String(value), .. } => Some(value)
    _ => None
  }
  let byte_size = match json {
    { "bytes": Number(value, ..), .. } => Some(value.to_int())
    _ => None
  }
  let created_at = match json {
    { "created_at": Number(value, ..), .. } => Some(value.to_int())
    _ => None
  }
  let expires_at = match json {
    { "expires_at": Number(value, ..), .. } => Some(value.to_int())
    _ => None
  }
  (filename, byte_size, created_at, expires_at)
}

///|
fn guard_openai_files_error(json : Json, context : String) -> Unit raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="\{context} failed: \{message}",
      data=json,
    )
  }
}

///|
async fn OpenAIFiles::fetch_metadata(
  self : OpenAIFiles,
  call_options : @provider.FilesV4GetFileMetadataCallOptions,
) -> @provider.FilesV4FileMetadata {
  @provider.check_cancellation(None)
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=self.file_url(call_options.file_id),
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let json = response.value
  guard_openai_files_error(json, "OpenAI Files metadata request")
  let id = match json {
    { "id": String(value), .. } => value
    _ => call_options.file_id
  }
  let (filename, byte_size, created_at, expires_at) = openai_files_lifecycle_fields(
    json,
  )
  @provider.FilesV4FileMetadata::new(
    file_id=id,
    media_type?=None,
    filename?,
    byte_size?,
    created_at?,
    expires_at?,
    provider_metadata=openai_files_lifecycle_metadata(json, id),
  )
}

///|
async fn OpenAIFiles::fetch_content(
  self : OpenAIFiles,
  call_options : @provider.FilesV4DownloadFileCallOptions,
) -> @provider.FilesV4DownloadFileResult {
  let content_url = @provider_utils.append_path(
    self.file_url(call_options.file_id),
    "/content",
  )
  let response = @provider_utils.get_bytes(
    provider_name=self.provider_name,
    url=content_url,
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    transport=self.http_transport,
  )
  @provider.FilesV4DownloadFileResult::new(
    file_id=call_options.file_id,
    data=response.value,
    media_type?=response.response.headers.get("content-type"),
    filename?=None,
    provider_metadata=Map([
      (
        "openai",
        Json::object(Map([("content_url", Json::string(content_url))])),
      ),
    ]),
  )
}

///|
async fn OpenAIFiles::remove(
  self : OpenAIFiles,
  call_options : @provider.FilesV4DeleteFileCallOptions,
) -> @provider.FilesV4DeleteFileResult {
  @provider.check_cancellation(None)
  let response = @provider_utils.delete_json(
    provider_name=self.provider_name,
    url=self.file_url(call_options.file_id),
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let json = response.value
  guard_openai_files_error(json, "OpenAI Files delete request")
  let deleted = match json {
    { "deleted": False, .. } => false
    _ => true
  }
  @provider.FilesV4DeleteFileResult::new(
    file_id=call_options.file_id,
    deleted~,
    provider_metadata=openai_files_lifecycle_metadata(
      json,
      call_options.file_id,
    ),
  )
}

///|
impl @provider.FilesV4 for OpenAIFiles with fn get_file_metadata(
  self,
  call_options,
) -> @provider.FilesV4FileMetadata raise {
  self.fetch_metadata(call_options)
}

///|
impl @provider.FilesV4 for OpenAIFiles with fn download_file(self, call_options) -> @provider.FilesV4DownloadFileResult raise {
  self.fetch_content(call_options)
}

///|
impl @provider.FilesV4 for OpenAIFiles with fn delete_file(self, call_options) -> @provider.FilesV4DeleteFileResult raise {
  self.remove(call_options)
}

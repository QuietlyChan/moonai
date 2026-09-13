///|
/// Typed DeepSeek Files upload options.
pub(all) struct DeepSeekFilesOptions {
  /// Number of seconds after creation before the file expires.
  /// Must be between one hour and thirty days.
  expires_after : Double?
} derive(Debug, Eq)

///|
/// Construct DeepSeek Files upload options.
pub fn DeepSeekFilesOptions::new(
  expires_after? : Double,
) -> DeepSeekFilesOptions raise {
  if expires_after is Some(value) {
    guard value >= 3600.0 && value <= 2_592_000.0 else {
      raise @provider.InvalidArgumentError(
        argument="expires_after",
        message="DeepSeek expiresAfter must be between one hour (3600) and thirty days (2592000) seconds.",
      )
    }
  }
  { expires_after, }
}

///|
/// Convert typed FilesV4 options into the DeepSeek provider namespace.
pub fn DeepSeekFilesOptions::to_provider_options(
  self : DeepSeekFilesOptions,
  provider_name? : String = "deepseek",
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.expires_after is Some(value) {
    values["expiresAfter"] = Json::number(value)
  }
  Map([(provider_name, Json::object(values))])
}

///|
/// DeepSeek Files API implementation.
///
/// DeepSeek accepts image uploads (JPEG, PNG, GIF, WebP) with
/// purpose=user_data for use as vision inputs in chat completions.
pub struct DeepSeekFiles {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct a DeepSeek Files API client directly.
pub fn deepseek_files(
  api_key? : String = "",
  base_url? : String,
  provider_name? : String = "deepseek.files",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> DeepSeekFiles {
  {
    provider_name,
    base_url: @provider_utils.without_trailing_slash(
      base_url.unwrap_or("https://api.deepseek.com"),
    ),
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Select the FilesV4 API from a DeepSeek provider factory.
pub fn DeepSeekProvider::files(self : DeepSeekProvider) -> DeepSeekFiles {
  deepseek_files(
    api_key=self.api_key,
    base_url=self.base_url,
    provider_name="\{self.provider_name}.files",
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
fn DeepSeekFiles::files_url(self : DeepSeekFiles) -> String {
  @provider_utils.append_path(self.base_url, "/files")
}

///|
fn DeepSeekFiles::request_headers(
  self : DeepSeekFiles,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer " + load_deepseek_api_key(self.api_key)
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/deepseek/\{VERSION}"],
  )
}

///|
priv struct ParsedDeepSeekFilesOptions {
  expires_after : Int?
  warnings : Array[@provider.Warning]
}

///|
fn parse_deepseek_files_options(
  provider_options : Map[String, Json],
) -> ParsedDeepSeekFilesOptions {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="deepseek",
    aliases=["deepseek"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let expires_after : Int? = match
    reader.take_double("expiresAfter", aliases=["expires_after"]) {
    Some(value) => {
      let seconds = value.to_int()
      if seconds >= 3600 && seconds <= 2_592_000 {
        Some(seconds)
      } else {
        reader.add_warning(
          @provider.Warning::Compatibility(
            feature="providerOptions.deepseek.expiresAfter",
            details="DeepSeek expiresAfter must be between one hour and thirty days; the invalid value was ignored.",
          ),
        )
        None
      }
    }
    None => None
  }
  { expires_after, warnings: reader.diagnostics(), }
}

///|
fn deepseek_files_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(value), .. }, .. } => Some(value)
    _ => None
  }
}

///|
fn guard_deepseek_files_size(file_bytes : Bytes) -> Unit raise {
  guard file_bytes.length() <= 67_108_864 else {
    raise @provider.InvalidArgumentError(
      argument="data",
      message="DeepSeek file uploads must not exceed 64 MiB (67108864 bytes). Received \{file_bytes.length()} bytes.",
    )
  }
}

///|
fn guard_deepseek_files_filename(filename : String) -> Unit raise {
  guard filename.length() <= 512 else {
    raise @provider.InvalidArgumentError(
      argument="filename",
      message="DeepSeek filenames must not exceed 512 characters. Received \{filename.length()} characters.",
    )
  }
}

///|
fn deepseek_files_normalize_media_type(media_type : String) -> String {
  match media_type.find(";") {
    Some(index) => media_type[:index].trim().to_lower().to_owned()
    None => media_type.trim().to_lower().to_owned()
  }
}

///|
fn deepseek_files_is_supported_image(media_type : String) -> Bool {
  media_type == "image/gif" ||
  media_type == "image/jpeg" ||
  media_type == "image/jpg" ||
  media_type == "image/png" ||
  media_type == "image/webp"
}

///|
fn deepseek_files_is_generic_media(media_type : String) -> Bool {
  media_type == "" ||
  media_type == "application/binary" ||
  media_type == "application/octet-stream" ||
  media_type == "binary/octet-stream" ||
  media_type == "image" ||
  media_type == "image/*"
}

///|
fn deepseek_files_has_supported_extension(filename : String?) -> Bool {
  match filename {
    Some(name) => {
      let segments = name.to_lower().split(".").to_array()
      let extension = segments[segments.length() - 1]
      extension == "gif" ||
      extension == "jpeg" ||
      extension == "jpg" ||
      extension == "png" ||
      extension == "webp"
    }
    None => false
  }
}

///|
fn guard_deepseek_files_media_type(
  media_type~ : String,
  filename~ : String?,
  file_bytes~ : Bytes,
) -> Unit raise {
  let normalized = deepseek_files_normalize_media_type(media_type)
  let detected = @provider_utils.detect_media_type(
    @provider_utils.convert_bytes_to_base64(file_bytes),
  )
  if detected is Some(value) && !deepseek_files_is_supported_image(value) {
    raise @provider.InvalidArgumentError(
      argument="data",
      message="DeepSeek file uploads support JPEG, PNG, GIF, and WebP images. Detected unsupported file content type \"\{value}\".",
    )
  }
  if deepseek_files_is_supported_image(normalized) {
    return
  }
  if deepseek_files_is_generic_media(normalized) {
    if detected is Some(_) || deepseek_files_has_supported_extension(filename) {
      return
    }
    raise @provider.InvalidArgumentError(
      argument="mediaType",
      message="DeepSeek file uploads support JPEG, PNG, GIF, and WebP images. Provide a supported media type or a filename ending in .jpg, .jpeg, .png, .gif, or .webp. Received \"\{media_type}\".",
    )
  }
  raise @provider.InvalidArgumentError(
    argument="mediaType",
    message="DeepSeek file uploads support JPEG, PNG, GIF, and WebP images. Received unsupported media type \"\{media_type}\".",
  )
}

///|
fn decode_deepseek_file_upload(
  json : Json,
  call_options : @provider.FilesV4UploadFileCallOptions,
  warnings~ : Array[@provider.Warning],
) -> @provider.FilesV4UploadFileResult raise {
  if deepseek_files_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="DeepSeek Files request failed: \{message}",
      data=json,
    )
  }
  let id = match json {
    { "id": String(value), .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="DeepSeek Files response has no file id",
        data=json,
      )
  }
  let filename = match json {
    { "filename": String(value), .. } => Some(value)
    _ => call_options.filename
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
  let metadata : Map[String, Json] = Map([])
  match json {
    { "object": String(value), .. } => metadata["object"] = Json::string(value)
    _ => ()
  }
  match json {
    { "filename": String(value), .. } =>
      metadata["filename"] = Json::string(value)
    _ => ()
  }
  match json {
    { "purpose": String(value), .. } =>
      metadata["purpose"] = Json::string(value)
    _ => ()
  }
  match json {
    { "bytes": Number(value, ..), .. } =>
      metadata["bytes"] = Json::number(value)
    _ => ()
  }
  match json {
    { "created_at": Number(value, ..), .. } =>
      metadata["createdAt"] = Json::number(value)
    _ => ()
  }
  match json {
    { "expires_at": Number(value, ..), .. } =>
      metadata["expiresAt"] = Json::number(value)
    _ => ()
  }
  let media_type = if call_options.media_type == "" {
    None
  } else {
    Some(call_options.media_type)
  }
  @provider.FilesV4UploadFileResult::new(
    provider_reference=@provider.ProviderReference::single(
      provider="deepseek",
      id~,
    ),
    media_type?,
    filename?,
    byte_size?,
    created_at?,
    expires_at?,
    provider_metadata=Map([("deepseek", Json::object(metadata))]),
    warnings~,
  )
}

///|
async fn DeepSeekFiles::upload(
  self : DeepSeekFiles,
  call_options : @provider.FilesV4UploadFileCallOptions,
) -> @provider.FilesV4UploadFileResult {
  let parsed = parse_deepseek_files_options(call_options.provider_options)
  let file_bytes = @provider_utils.collect_upload_file_data(call_options.data)
  guard_deepseek_files_size(file_bytes)
  match call_options.filename {
    Some(name) => guard_deepseek_files_filename(name)
    None => ()
  }
  guard_deepseek_files_media_type(
    media_type=call_options.media_type,
    filename=call_options.filename,
    file_bytes~,
  )
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::file(
      name="file",
      filename=call_options.filename.unwrap_or("blob"),
      media_type=call_options.media_type,
      data=file_bytes,
    ),
    @provider_utils.MultipartField::text(name="purpose", value="user_data"),
  ]
  if parsed.expires_after is Some(seconds) {
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
  let form_data = @provider_utils.encode_multipart_form_data(fields)
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=self.files_url(),
    headers=self.request_headers(),
    form_data~,
    timeout_ms=self.idle_timeout_ms,
    error_to_message=deepseek_files_error_message,
    transport=self.http_transport,
  )
  @provider_utils.handle_json_response(response, value => {
    decode_deepseek_file_upload(value, call_options, warnings=parsed.warnings)
  })
}

///|
pub impl @provider.FilesV4 for DeepSeekFiles with fn specification_version(
  _self : DeepSeekFiles,
) -> String {
  "v4"
}

///|
pub impl @provider.FilesV4 for DeepSeekFiles with fn provider(
  self : DeepSeekFiles,
) -> String {
  self.provider_name
}

///|
pub impl @provider.FilesV4 for DeepSeekFiles with fn upload_file(
  self : DeepSeekFiles,
  options : @provider.FilesV4UploadFileCallOptions,
) -> @provider.FilesV4UploadFileResult {
  self.upload(options)
}

///|
pub impl @provider.FilesV4 for DeepSeekFiles with fn get_file_metadata(
  _self : DeepSeekFiles,
  _call_options : @provider.FilesV4GetFileMetadataCallOptions,
) -> @provider.FilesV4FileMetadata raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="DeepSeek Files metadata retrieval",
  )
}

///|
pub impl @provider.FilesV4 for DeepSeekFiles with fn download_file(
  _self : DeepSeekFiles,
  _call_options : @provider.FilesV4DownloadFileCallOptions,
) -> @provider.FilesV4DownloadFileResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="DeepSeek Files downloads",
  )
}

///|
pub impl @provider.FilesV4 for DeepSeekFiles with fn delete_file(
  _self : DeepSeekFiles,
  _call_options : @provider.FilesV4DeleteFileCallOptions,
) -> @provider.FilesV4DeleteFileResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="DeepSeek Files deletion",
  )
}

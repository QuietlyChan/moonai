///|
/// The xAI files surface: /files multipart upload, metadata, binary
/// download, and delete. File references use `{ xai: fileId }` entries.
struct XaiFiles {
  provider_name : String
  api_key : String
  base_url : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn xai_files_value(
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> XaiFiles {
  {
    provider_name: "xai",
    api_key,
    base_url,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Extract the xai file id from the file reference in call options.
fn xai_files_file_id(
  options_provider_options~ : Map[String, Json],
) -> String raise {
  match options_provider_options.get("xai") {
    Some(String(file_id)) if file_id.trim() != "" => file_id
    _ =>
      raise @provider.InvalidArgumentError(
        argument="file",
        message="file reference is missing an 'xai' file id.",
      )
  }
}

///|
fn XaiFiles::file_headers(
  self : XaiFiles,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="XAI_API_KEY",
    description="xAI",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([("Authorization", "Bearer \{api_key}")]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Decode a file resource JSON ({id, filename, bytes, created_at,
/// expires_at}).
fn decode_xai_file_resource(
  value : Json,
) -> (String, String?, Int?, Int?) raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match value {
    { "id": String(id), .. } => {
      let filename = match value {
        { "filename": String(name), .. } => Some(name)
        _ => None
      }
      let bytes = match value {
        { "bytes": Number(count, ..), .. } => Some(count.to_int())
        _ => None
      }
      let created_at = match value {
        { "created_at": Number(seconds, ..), .. } => Some(seconds.to_int())
        _ => None
      }
      (id, filename, bytes, created_at)
    }
    _ => fail("xai file response missing id")
  }
}

///|
/// Whether the upload payload is a stream (unsupported in the native port
/// without a streaming multipart transport for this surface).
fn xai_file_data_inline(data : @provider.UploadFileData) -> Bytes? {
  match data {
    @provider.UploadFileBytes(bytes) => Some(bytes)
    @provider.UploadFileBase64(payload) =>
      Some(@base64.decode(payload)) catch {
        _ => None
      }
    @provider.UploadFileText(text) => Some(@utf8.encode(text))
    @provider.UploadFileStream(_) => None
  }
}

///|
pub impl @provider.FilesV4 for XaiFiles with fn specification_version(_self) -> String {
  "v4"
}

///|
pub impl @provider.FilesV4 for XaiFiles with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.FilesV4 for XaiFiles with fn upload_file(self, options) -> @provider.FilesV4UploadFileResult raise {
  let inline = xai_file_data_inline(options.data)
  guard inline is Some(bytes) else {
    raise @provider.UnsupportedFunctionalityError(
      functionality="xAI streaming file upload",
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  let fields : Array[@provider_utils.MultipartField] = []
  if resolution.values.get("expiresAfter") is Some(value) {
    match value {
      Number(count, ..) =>
        fields.push(
          @provider_utils.MultipartField::text(
            name="expires_after",
            value=count.to_string(),
          ),
        )
      _ => ()
    }
  }
  match resolution.values.get("team_id") {
    Some(String(team)) =>
      fields.push(
        @provider_utils.MultipartField::text(name="team_id", value=team),
      )
    _ => ()
  }
  fields.push(
    @provider_utils.MultipartField::file(
      name="file",
      filename=options.filename.unwrap_or("file"),
      media_type=options.media_type,
      data=bytes,
    ),
  )
  let form_data = @provider_utils.encode_multipart_form_data(fields)
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/files"),
    headers=self.file_headers(extra=options.headers),
    form_data~,
    timeout_ms=self.idle_timeout_ms,
    error_to_message=xai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (file_id, filename, byte_size, created_at) = @provider_utils.handle_json_response(
    response, decode_xai_file_resource,
  )
  @provider.FilesV4UploadFileResult::new(
    provider_reference=@provider.ProviderReference::single(
      provider="xai",
      id=file_id,
    ),
    media_type=options.media_type,
    filename?=match filename {
      Some(name) => Some(name)
      None => options.filename
    },
    byte_size?,
    created_at?,
  )
}

///|
pub impl @provider.FilesV4 for XaiFiles with fn get_file_metadata(self, options) -> @provider.FilesV4FileMetadata raise {
  let file_id = xai_files_file_id(
    options_provider_options=options.provider_options,
  )
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/files/\{file_id}"),
    headers=self.file_headers(extra=options.headers),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=xai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (resolved_id, filename, byte_size, created_at) = @provider_utils.handle_json_response(
    response, decode_xai_file_resource,
  )
  @provider.FilesV4FileMetadata::new(
    file_id=resolved_id,
    filename?,
    byte_size?,
    created_at?,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
  )
}

///|
pub impl @provider.FilesV4 for XaiFiles with fn download_file(self, options) -> @provider.FilesV4DownloadFileResult raise {
  let file_id = xai_files_file_id(
    options_provider_options=options.provider_options,
  )
  let response = @provider_utils.get_bytes(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/files/\{file_id}/content"),
    headers=self.file_headers(extra=options.headers),
    timeout_ms=self.idle_timeout_ms,
    transport=self.http_transport,
  )
  let media_type = match response.response.headers.get("content-type") {
    Some(value) =>
      match value.split(";").to_array().get(0) {
        Some(first) => Some(first.trim().to_owned())
        None => None
      }
    None => None
  }
  @provider.FilesV4DownloadFileResult::new(
    file_id~,
    data=response.value,
    media_type?,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      Json::object(Map([])),
      self.provider_name,
    ),
  )
}

///|
pub impl @provider.FilesV4 for XaiFiles with fn delete_file(self, options) -> @provider.FilesV4DeleteFileResult raise {
  let response = @provider_utils.delete_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/files/\{options.file_id}"),
    headers=self.file_headers(extra=options.headers),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=xai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  ignore(response)
  @provider.FilesV4DeleteFileResult::new(file_id=options.file_id, deleted=true)
}

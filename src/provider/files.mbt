///|
/// Inline data accepted by a provider file-upload interface.
pub(all) enum UploadFileData {
  UploadFileBytes(Bytes)
  UploadFileBase64(String)
  UploadFileText(String)
} derive(Debug, Eq)

///|
/// Construct raw-byte upload data.
pub fn UploadFileData::bytes(data : Bytes) -> UploadFileData {
  UploadFileBytes(data)
}

///|
/// Construct Base64-encoded upload data.
pub fn UploadFileData::base64(data : String) -> UploadFileData {
  UploadFileBase64(data)
}

///|
/// Construct UTF-8 text upload data.
pub fn UploadFileData::text(text : String) -> UploadFileData {
  UploadFileText(text)
}

///|
/// Provider-level options for uploading one file.
pub(all) struct FilesV4UploadFileCallOptions {
  data : UploadFileData
  media_type : String
  filename : String?
  provider_options : Map[String, Json]
  headers : Map[String, String]
} derive(Debug, Eq)

///|
/// Construct one provider-level file upload call.
pub fn FilesV4UploadFileCallOptions::new(
  data~ : UploadFileData,
  media_type~ : String,
  filename? : String,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
) -> FilesV4UploadFileCallOptions {
  { data, media_type, filename, provider_options, headers, }
}

///|
/// Result returned after a provider accepts an uploaded file.
pub(all) struct FilesV4UploadFileResult {
  provider_reference : ProviderReference
  media_type : String?
  filename : String?
  byte_size : Int?
  created_at : Int?
  expires_at : Int?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a provider file-upload result.
pub fn FilesV4UploadFileResult::new(
  provider_reference~ : ProviderReference,
  media_type? : String,
  filename? : String,
  byte_size? : Int,
  created_at? : Int,
  expires_at? : Int,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> FilesV4UploadFileResult {
  {
    provider_reference,
    media_type,
    filename,
    byte_size,
    created_at,
    expires_at,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Call options for reading one stored file's metadata.
pub(all) struct FilesV4GetFileMetadataCallOptions {
  file_id : String
  provider_options : Map[String, Json]
  headers : Map[String, String]
} derive(Debug, Eq)

///|
/// Construct one file-metadata call.
pub fn FilesV4GetFileMetadataCallOptions::new(
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
) -> FilesV4GetFileMetadataCallOptions {
  { file_id, provider_options, headers, }
}

///|
/// Metadata describing one stored provider file.
pub(all) struct FilesV4FileMetadata {
  file_id : String
  media_type : String?
  filename : String?
  byte_size : Int?
  created_at : Int?
  expires_at : Int?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct one file-metadata result.
pub fn FilesV4FileMetadata::new(
  file_id~ : String,
  media_type? : String,
  filename? : String,
  byte_size? : Int,
  created_at? : Int,
  expires_at? : Int,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> FilesV4FileMetadata {
  {
    file_id,
    media_type,
    filename,
    byte_size,
    created_at,
    expires_at,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Call options for downloading one stored file's content.
pub(all) struct FilesV4DownloadFileCallOptions {
  file_id : String
  provider_options : Map[String, Json]
  headers : Map[String, String]
} derive(Debug, Eq)

///|
/// Construct one file-download call.
pub fn FilesV4DownloadFileCallOptions::new(
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
) -> FilesV4DownloadFileCallOptions {
  { file_id, provider_options, headers, }
}

///|
/// Downloaded file payload together with its lifecycle metadata.
pub(all) struct FilesV4DownloadFileResult {
  file_id : String
  data : Bytes
  media_type : String?
  filename : String?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct one file-download result.
pub fn FilesV4DownloadFileResult::new(
  file_id~ : String,
  data~ : Bytes,
  media_type? : String,
  filename? : String,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> FilesV4DownloadFileResult {
  {
    file_id,
    data,
    media_type,
    filename,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Call options for deleting one stored file.
pub(all) struct FilesV4DeleteFileCallOptions {
  file_id : String
  provider_options : Map[String, Json]
  headers : Map[String, String]
} derive(Debug, Eq)

///|
/// Construct one file-delete call.
pub fn FilesV4DeleteFileCallOptions::new(
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
) -> FilesV4DeleteFileCallOptions {
  { file_id, provider_options, headers, }
}

///|
/// Result reported after a provider deletes (or reports missing) a file.
pub(all) struct FilesV4DeleteFileResult {
  file_id : String
  deleted : Bool
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct one file-delete result.
pub fn FilesV4DeleteFileResult::new(
  file_id~ : String,
  deleted~ : Bool,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> FilesV4DeleteFileResult {
  {
    file_id,
    deleted,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

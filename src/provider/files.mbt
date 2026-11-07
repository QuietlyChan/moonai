///|
/// Pull-based byte source for streaming uploads.
///
/// Providers currently drain the stream into memory before encoding the
/// request, so callers gain chunked sourcing rather than O(1) memory; the
/// `size_hint_bytes` declaration is reserved for transports that can stream
/// the request body incrementally.
pub(open) trait UploadByteStream {
  /// Read the next chunk; `None` ends the stream.
  async fn read_chunk(Self) -> Bytes?
  /// Total payload size in bytes when declared up front; `None` otherwise.
  fn size_hint_bytes(Self) -> Int64?
}

///|
impl Debug for &UploadByteStream with fn to_repr(_self) {
  Repr::Repr("UploadByteStream(<stream>)")
}

///|
/// Inline data accepted by a provider file-upload interface.
#derive(Debug)
pub(all) enum UploadFileData {
  UploadFileBytes(Bytes)
  UploadFileBase64(String)
  UploadFileText(String)
  UploadFileStream(&UploadByteStream)
}

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
/// Construct streaming upload data from a chunked byte source.
pub fn UploadFileData::stream(stream : &UploadByteStream) -> UploadFileData {
  UploadFileStream(stream)
}

///|
/// Provider-level options for uploading one file.
#derive(Debug)
pub(all) struct FilesV4UploadFileCallOptions {
  data : UploadFileData
  media_type : String
  filename : String?
  provider_options : Map[String, Json]
  headers : Map[String, String]
}

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
#derive(Debug, Eq)
pub(all) struct FilesV4UploadFileResult {
  provider_reference : ProviderReference
  media_type : String?
  filename : String?
  byte_size : Int32?
  created_at : Int32?
  expires_at : Int32?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
}

///|
/// Construct a provider file-upload result.
pub fn FilesV4UploadFileResult::new(
  provider_reference~ : ProviderReference,
  media_type? : String,
  filename? : String,
  byte_size? : Int32,
  created_at? : Int32,
  expires_at? : Int32,
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
#derive(Debug, Eq)
pub(all) struct FilesV4GetFileMetadataCallOptions {
  file_id : String
  provider_options : Map[String, Json]
  headers : Map[String, String]
}

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
#derive(Debug, Eq)
pub(all) struct FilesV4FileMetadata {
  file_id : String
  media_type : String?
  filename : String?
  byte_size : Int32?
  created_at : Int32?
  expires_at : Int32?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
}

///|
/// Construct one file-metadata result.
pub fn FilesV4FileMetadata::new(
  file_id~ : String,
  media_type? : String,
  filename? : String,
  byte_size? : Int32,
  created_at? : Int32,
  expires_at? : Int32,
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
#derive(Debug, Eq)
pub(all) struct FilesV4DownloadFileCallOptions {
  file_id : String
  provider_options : Map[String, Json]
  headers : Map[String, String]
}

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
#derive(Debug, Eq)
pub(all) struct FilesV4DownloadFileResult {
  file_id : String
  data : Bytes
  media_type : String?
  filename : String?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
}

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
#derive(Debug, Eq)
pub(all) struct FilesV4DeleteFileCallOptions {
  file_id : String
  provider_options : Map[String, Json]
  headers : Map[String, String]
}

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
#derive(Debug, Eq)
pub(all) struct FilesV4DeleteFileResult {
  file_id : String
  deleted : Bool
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
}

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

///|
pub extend UploadFileData with Debug::{to_repr}

///|
pub extend FilesV4UploadFileCallOptions with Debug::{to_repr}

///|
pub extend FilesV4UploadFileResult with Debug::{to_repr}

///|
pub extend FilesV4UploadFileResult with Eq::{not_equal, equal}

///|
pub extend FilesV4GetFileMetadataCallOptions with Debug::{to_repr}

///|
pub extend FilesV4GetFileMetadataCallOptions with Eq::{not_equal, equal}

///|
pub extend FilesV4FileMetadata with Debug::{to_repr}

///|
pub extend FilesV4FileMetadata with Eq::{not_equal, equal}

///|
pub extend FilesV4DownloadFileCallOptions with Debug::{to_repr}

///|
pub extend FilesV4DownloadFileCallOptions with Eq::{not_equal, equal}

///|
pub extend FilesV4DownloadFileResult with Debug::{to_repr}

///|
pub extend FilesV4DownloadFileResult with Eq::{not_equal, equal}

///|
pub extend FilesV4DeleteFileCallOptions with Debug::{to_repr}

///|
pub extend FilesV4DeleteFileCallOptions with Eq::{not_equal, equal}

///|
pub extend FilesV4DeleteFileResult with Debug::{to_repr}

///|
pub extend FilesV4DeleteFileResult with Eq::{not_equal, equal}

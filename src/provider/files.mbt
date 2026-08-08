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
} derive(Debug, Eq)

///|
/// Construct one provider-level file upload call.
pub fn FilesV4UploadFileCallOptions::new(
  data~ : UploadFileData,
  media_type~ : String,
  filename? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4UploadFileCallOptions {
  { data, media_type, filename, provider_options }
}

///|
/// Result returned after a provider accepts an uploaded file.
pub(all) struct FilesV4UploadFileResult {
  provider_reference : ProviderReference
  media_type : String?
  filename : String?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a provider file-upload result.
pub fn FilesV4UploadFileResult::new(
  provider_reference~ : ProviderReference,
  media_type? : String,
  filename? : String,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> FilesV4UploadFileResult {
  {
    provider_reference,
    media_type,
    filename,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Upload a file through a provider's files interface.
pub async fn upload_file(
  files : &FilesV4,
  data~ : UploadFileData,
  media_type~ : String,
  filename? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4UploadFileResult {
  guard media_type.trim() != "" else {
    fail("upload_file requires a non-empty media_type")
  }
  files.upload_file(
    FilesV4UploadFileCallOptions::new(
      data~,
      media_type~,
      filename?,
      provider_options~,
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `upload_file`.
pub async fn uploadFile(
  files : &FilesV4,
  data~ : UploadFileData,
  media_type~ : String,
  filename? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4UploadFileResult {
  upload_file(files, data~, media_type~, filename?, provider_options~)
}

///|
/// Read one stored file's metadata through a provider's files interface.
///
/// Raises `UnsupportedFunctionalityError` when the provider does not expose
/// a metadata endpoint.
pub async fn get_file_metadata(
  files : &FilesV4,
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4FileMetadata {
  guard file_id.trim() != "" else {
    fail("get_file_metadata requires a non-empty file_id")
  }
  files.get_file_metadata(
    FilesV4GetFileMetadataCallOptions::new(file_id~, provider_options~),
  )
}

///|
/// AI SDK-style camel-case spelling for `get_file_metadata`.
pub async fn getFileMetadata(
  files : &FilesV4,
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4FileMetadata {
  get_file_metadata(files, file_id~, provider_options~)
}

///|
/// Download one stored file's content through a provider's files interface.
///
/// Raises `UnsupportedFunctionalityError` when the provider does not expose
/// a download endpoint.
pub async fn download_file(
  files : &FilesV4,
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4DownloadFileResult {
  guard file_id.trim() != "" else {
    fail("download_file requires a non-empty file_id")
  }
  files.download_file(
    FilesV4DownloadFileCallOptions::new(file_id~, provider_options~),
  )
}

///|
/// AI SDK-style camel-case spelling for `download_file`.
pub async fn downloadFile(
  files : &FilesV4,
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4DownloadFileResult {
  download_file(files, file_id~, provider_options~)
}

///|
/// Delete one stored file through a provider's files interface.
///
/// Raises `UnsupportedFunctionalityError` when the provider does not expose
/// a delete endpoint.
pub async fn delete_file(
  files : &FilesV4,
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4DeleteFileResult {
  guard file_id.trim() != "" else {
    fail("delete_file requires a non-empty file_id")
  }
  files.delete_file(
    FilesV4DeleteFileCallOptions::new(file_id~, provider_options~),
  )
}

///|
/// AI SDK-style camel-case spelling for `delete_file`.
pub async fn deleteFile(
  files : &FilesV4,
  file_id~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> FilesV4DeleteFileResult {
  delete_file(files, file_id~, provider_options~)
}

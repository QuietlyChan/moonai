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

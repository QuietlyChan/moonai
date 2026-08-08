///|
fn base64_data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}

///|
/// Convert a V4 image-model file to the URL representation expected by JSON
/// provider protocols. URL inputs pass through unchanged; inline inputs become
/// Base64 data URIs.
pub fn convert_image_model_file_to_data_uri(
  file : @provider.ImageModelV4File,
) -> String {
  match file {
    @provider.ImageV4Url(url~) => url
    @provider.ImageV4Data(data~, media_type~) =>
      base64_data_uri(media_type, data)
    @provider.ImageV4Bytes(data~, media_type~) =>
      base64_data_uri(media_type, convert_bytes_to_base64(data))
  }
}

///|
/// AI SDK-style spelling of `convert_image_model_file_to_data_uri`.
pub fn convertImageModelFileToDataUri(
  file : @provider.ImageModelV4File,
) -> String {
  convert_image_model_file_to_data_uri(file)
}

///|
/// Video V4 files are structurally compatible with image-model files in the
/// TypeScript AI SDK. MoonBit uses nominal enums, so the video contract has an
/// explicit companion converter with the same URL/data-URI semantics.
pub fn convert_video_model_file_to_data_uri(
  file : @provider.VideoModelV4File,
) -> String {
  match file {
    @provider.VideoV4Url(url~, ..) => url
    @provider.VideoV4Data(data~, media_type~, ..) =>
      base64_data_uri(media_type, data)
    @provider.VideoV4Bytes(data~, media_type~, ..) =>
      base64_data_uri(media_type, convert_bytes_to_base64(data))
  }
}

///|
/// Camel-case alias for `convert_video_model_file_to_data_uri`.
pub fn convertVideoModelFileToDataUri(
  file : @provider.VideoModelV4File,
) -> String {
  convert_video_model_file_to_data_uri(file)
}

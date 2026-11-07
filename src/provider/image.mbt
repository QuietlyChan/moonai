///|
/// The payload returned for a generated image.
#derive(Debug, Eq)
pub(all) enum ImageData {
  Base64(String)
  Url(String)
}

///|
/// An image supplied for editing, variation, or inpainting.
#derive(Debug, Eq)
pub(all) enum ImageFile {
  ImageFileBase64(data~ : String, media_type~ : String, filename~ : String)
  ImageFileBytes(data~ : Bytes, media_type~ : String, filename~ : String)
  ImageFileUrl(url~ : String, filename~ : String)
}

///|
/// Construct a base64-backed image input file.
pub fn ImageFile::base64(
  data~ : String,
  media_type~ : String,
  filename? : String = "image",
) -> ImageFile {
  ImageFileBase64(data~, media_type~, filename~)
}

///|
/// Construct a binary image input file.
pub fn ImageFile::bytes(
  data~ : Bytes,
  media_type~ : String,
  filename? : String = "image",
) -> ImageFile {
  ImageFileBytes(data~, media_type~, filename~)
}

///|
/// Construct a URL-backed image input file.
pub fn ImageFile::url(url~ : String, filename? : String = "image") -> ImageFile {
  ImageFileUrl(url~, filename~)
}

///|
/// One generated image and optional provider-revised prompt.
#derive(Debug, Eq)
pub(all) struct GeneratedImage {
  data : ImageData
  revised_prompt : String?
}

///|
/// Construct one generated image.
pub fn GeneratedImage::new(
  data : ImageData,
  revised_prompt? : String,
) -> GeneratedImage {
  { data, revised_prompt, }
}

///|
/// Options passed to one provider image request.
#derive(Debug)
pub(all) struct ImageCallOptions {
  prompt : String
  n : Int32
  size : String?
  aspect_ratio : String?
  seed : Int32?
  files : Array[ImageFile]
  mask : ImageFile?
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
}

///|
/// Construct normalized image generation options.
pub fn ImageCallOptions::new(
  prompt : String,
  n? : Int32 = 1,
  size? : String,
  aspect_ratio? : String,
  seed? : Int32,
  files? : Array[ImageFile] = [],
  mask? : ImageFile,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ImageCallOptions {
  {
    prompt,
    n,
    size,
    aspect_ratio,
    seed,
    files,
    mask,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Result returned by an image generation call.
#derive(Debug, Eq)
pub(all) struct ImageResponse {
  images : Array[GeneratedImage]
  usage : Usage
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
}

///|
/// Construct an image response without transport diagnostics.
pub fn ImageResponse::new(
  images : Array[GeneratedImage],
  usage : Usage,
) -> ImageResponse {
  {
    images,
    usage,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach diagnostics to an image result.
pub fn ImageResponse::with_diagnostics(
  self : ImageResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> ImageResponse {
  {
    images: self.images,
    usage: self.usage,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add HTTP metadata to an image result.
pub fn ImageResponse::with_transport(
  self : ImageResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> ImageResponse {
  {
    images: self.images,
    usage: self.usage,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}

///|
pub extend ImageData with Debug::{to_repr}

///|
pub extend ImageData with Eq::{not_equal, equal}

///|
pub extend ImageFile with Debug::{to_repr}

///|
pub extend ImageFile with Eq::{not_equal, equal}

///|
pub extend GeneratedImage with Debug::{to_repr}

///|
pub extend GeneratedImage with Eq::{not_equal, equal}

///|
pub extend ImageCallOptions with Debug::{to_repr}

///|
pub extend ImageResponse with Debug::{to_repr}

///|
pub extend ImageResponse with Eq::{not_equal, equal}

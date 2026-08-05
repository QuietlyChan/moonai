///|
/// The payload returned for a generated image.
pub(all) enum ImageData {
  Base64(String)
  Url(String)
} derive(Debug, Eq)

///|
/// An image supplied for editing, variation, or inpainting.
pub(all) enum ImageFile {
  ImageFileBase64(data~ : String, media_type~ : String, filename~ : String)
  ImageFileBytes(data~ : Bytes, media_type~ : String, filename~ : String)
  ImageFileUrl(url~ : String, filename~ : String)
} derive(Debug, Eq)

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
pub(all) struct GeneratedImage {
  data : ImageData
  revised_prompt : String?
} derive(Debug, Eq)

///|
/// Construct one generated image.
pub fn GeneratedImage::new(
  data : ImageData,
  revised_prompt? : String,
) -> GeneratedImage {
  { data, revised_prompt }
}

///|
/// Options passed to one provider image request.
pub(all) struct ImageCallOptions {
  prompt : String
  n : Int
  size : String?
  aspect_ratio : String?
  seed : Int?
  files : Array[ImageFile]
  mask : ImageFile?
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct normalized image generation options.
pub fn ImageCallOptions::new(
  prompt : String,
  n? : Int = 1,
  size? : String,
  aspect_ratio? : String,
  seed? : Int,
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
pub(all) struct ImageResponse {
  images : Array[GeneratedImage]
  usage : Usage
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

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

///|
/// V4 input file used for image edits, variations, and masks.
///
/// The payload deliberately has no filename because AI SDK's V4 contract
/// models image files as data or URLs. Protocol adapters choose a multipart
/// filename when their endpoint requires one.
pub(all) enum ImageModelV4File {
  ImageV4Data(data~ : String, media_type~ : String)
  ImageV4Bytes(data~ : Bytes, media_type~ : String)
  ImageV4Url(url~ : String)
} derive(Debug, Eq)

///|
/// Construct a Base64-backed V4 image input.
pub fn ImageModelV4File::base64(
  data~ : String,
  media_type~ : String,
) -> ImageModelV4File {
  ImageV4Data(data~, media_type~)
}

///|
/// Construct a binary V4 image input.
pub fn ImageModelV4File::bytes(
  data~ : Bytes,
  media_type~ : String,
) -> ImageModelV4File {
  ImageV4Bytes(data~, media_type~)
}

///|
/// Construct a URL-backed V4 image input.
pub fn ImageModelV4File::url(url : String) -> ImageModelV4File {
  ImageV4Url(url~)
}

///|
/// Convert a V4 image file at the explicit protocol adapter boundary.
pub fn ImageModelV4File::to_image_file(
  self : ImageModelV4File,
  filename? : String = "image",
) -> ImageFile {
  match self {
    ImageV4Data(data~, media_type~) =>
      ImageFile::base64(data~, media_type~, filename~)
    ImageV4Bytes(data~, media_type~) =>
      ImageFile::bytes(data~, media_type~, filename~)
    ImageV4Url(url~) => ImageFile::url(url~, filename~)
  }
}

///|
/// Convert an existing image file to the V4 representation.
pub fn ImageModelV4File::from_image_file(file : ImageFile) -> ImageModelV4File {
  match file {
    ImageFileBase64(data~, media_type~, ..) => ImageV4Data(data~, media_type~)
    ImageFileBytes(data~, media_type~, ..) => ImageV4Bytes(data~, media_type~)
    ImageFileUrl(url~, ..) => ImageV4Url(url~)
  }
}

///|
/// Options passed to `ImageModelV4::do_generate`.
pub(all) struct ImageModelV4CallOptions {
  prompt : String?
  n : Int
  size : String?
  aspect_ratio : String?
  seed : Int?
  files : Array[ImageModelV4File]?
  mask : ImageModelV4File?
  provider_options : Map[String, Json]
  headers : Map[String, String]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct V4 image generation options.
pub fn ImageModelV4CallOptions::new(
  prompt? : String,
  n? : Int = 1,
  size? : String,
  aspect_ratio? : String,
  seed? : Int,
  files? : Array[ImageModelV4File],
  mask? : ImageModelV4File,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ImageModelV4CallOptions {
  {
    prompt,
    n,
    size,
    aspect_ratio,
    seed,
    files,
    mask,
    provider_options,
    headers,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Image token usage in the V4 contract.
pub(all) struct ImageModelV4Usage {
  input_tokens : Int?
  output_tokens : Int?
  total_tokens : Int?
} derive(Debug, Eq)

///|
/// Construct V4 image usage.
pub fn ImageModelV4Usage::new(
  input_tokens? : Int,
  output_tokens? : Int,
  total_tokens? : Int,
) -> ImageModelV4Usage {
  { input_tokens, output_tokens, total_tokens }
}

///|
/// Result of an image generation call through the V4 contract.
pub(all) struct ImageModelV4Result {
  images : Array[GeneratedImage]
  warnings : Array[Warning]
  provider_metadata : Map[String, Json]
  request : RequestMetadata?
  response : ResponseMetadata?
  usage : ImageModelV4Usage?
} derive(Debug, Eq)

///|
/// Construct a V4 image result.
pub fn ImageModelV4Result::new(
  images : Array[GeneratedImage],
  warnings? : Array[Warning] = [],
  provider_metadata? : Map[String, Json] = Map([]),
  request? : RequestMetadata,
  response? : ResponseMetadata,
  usage? : ImageModelV4Usage,
) -> ImageModelV4Result {
  {
    images,
    warnings: copy_warnings(warnings),
    provider_metadata: copy_provider_metadata(provider_metadata),
    request,
    response,
    usage,
  }
}

///|
/// Convert a protocol response at the explicit legacy wire boundary.
pub fn ImageModelV4Result::from_image_response(
  response : ImageResponse,
) -> ImageModelV4Result {
  ImageModelV4Result::new(
    response.images,
    warnings=response.warnings,
    provider_metadata=response.provider_metadata,
    request?=response.request,
    response?=response.response,
    usage=ImageModelV4Usage::new(
      input_tokens=response.usage.input_tokens,
      output_tokens=response.usage.output_tokens,
      total_tokens=response.usage.total_tokens,
    ),
  )
}

///|
/// Convert a V4 result to the high-level result shape used by the current
/// MoonBit API surface.
pub fn ImageModelV4Result::to_image_response(
  self : ImageModelV4Result,
) -> ImageResponse {
  let usage = match self.usage {
    Some(value) =>
      Usage::new(
        input_tokens=value.input_tokens.unwrap_or(0),
        output_tokens=value.output_tokens.unwrap_or(0),
        total_tokens?=value.total_tokens,
      )
    None => Usage::zero()
  }
  ImageResponse::new(self.images, usage).with_diagnostics(
    self.request,
    self.response,
    self.provider_metadata,
    self.warnings,
  )
}

///|
/// V4 image model contract corresponding to AI SDK's `ImageModelV4`.
pub(open) trait ImageModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_images_per_call(Self) -> Int?
  async fn do_generate(Self, ImageModelV4CallOptions) -> ImageModelV4Result
}

///|
/// A file that can be used as an image, video, or frame input to a video model.
pub(all) enum VideoInput {
  Url(url~ : String, media_type~ : String?)
  Base64(data~ : String, media_type~ : String)
} derive(Debug, Eq)

///|
/// Construct a URL-backed video input.
pub fn VideoInput::url(url : String, media_type? : String) -> VideoInput {
  Url(url~, media_type~)
}

///|
/// Construct a base64-backed video input.
pub fn VideoInput::base64(data~ : String, media_type~ : String) -> VideoInput {
  Base64(data~, media_type~)
}

///|
/// The semantic role of a frame image in a video request.
pub(all) enum VideoFrameType {
  FirstFrame
  LastFrame
} derive(Debug, Eq)

///|
/// A role-tagged frame image for first/last-frame generation.
pub(all) struct VideoFrameImage {
  image : VideoInput
  frame_type : VideoFrameType
} derive(Debug, Eq)

///|
/// Construct a frame image descriptor.
pub fn VideoFrameImage::new(
  image : VideoInput,
  frame_type : VideoFrameType,
) -> VideoFrameImage {
  { image, frame_type }
}

///|
/// Generated video payload. URLs are preferred because video providers usually
/// return large objects outside the JSON response body.
pub(all) enum GeneratedVideoData {
  Url(String)
  Base64(String)
  Binary(Bytes)
} derive(Debug, Eq)

///|
/// One generated video and its media type.
pub(all) struct GeneratedVideo {
  data : GeneratedVideoData
  media_type : String
} derive(Debug, Eq)

///|
/// Construct one generated video.
pub fn GeneratedVideo::new(
  data : GeneratedVideoData,
  media_type : String,
) -> GeneratedVideo {
  { data, media_type }
}

///|
/// Options passed to one provider video request.
pub(all) struct VideoCallOptions {
  prompt : String
  n : Int
  aspect_ratio : String?
  resolution : String?
  duration : Double?
  fps : Int?
  seed : Int?
  image : VideoInput?
  frame_images : Array[VideoFrameImage]
  input_references : Array[VideoInput]
  generate_audio : Bool?
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct normalized video generation options.
pub fn VideoCallOptions::new(
  prompt : String,
  n? : Int = 1,
  aspect_ratio? : String,
  resolution? : String,
  duration? : Double,
  fps? : Int,
  seed? : Int,
  image? : VideoInput,
  frame_images? : Array[VideoFrameImage] = [],
  input_references? : Array[VideoInput] = [],
  generate_audio? : Bool,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoCallOptions {
  {
    prompt,
    n,
    aspect_ratio,
    resolution,
    duration,
    fps,
    seed,
    image,
    frame_images,
    input_references,
    generate_audio,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Result returned by a video generation call.
pub(all) struct VideoResponse {
  videos : Array[GeneratedVideo]
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a video response without transport diagnostics.
pub fn VideoResponse::new(videos : Array[GeneratedVideo]) -> VideoResponse {
  {
    videos,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach provider and request diagnostics to a video result.
pub fn VideoResponse::with_diagnostics(
  self : VideoResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> VideoResponse {
  {
    videos: self.videos,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add transport metadata while preserving provider diagnostics.
pub fn VideoResponse::with_transport(
  self : VideoResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> VideoResponse {
  {
    videos: self.videos,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}

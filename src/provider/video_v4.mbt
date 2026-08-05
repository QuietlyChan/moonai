///|
/// A URL, inline Base64 value, or binary file accepted by a V4 video model.
///
/// `provider_options` is kept on the file because the AI SDK V4 contract allows
/// providers to attach options to individual input parts. Protocol adapters
/// that do not support per-file options may ignore the map at their wire edge.
pub(all) enum VideoModelV4File {
  VideoV4Data(
    data~ : String,
    media_type~ : String,
    provider_options~ : Map[String, Json]
  )
  VideoV4Bytes(
    data~ : Bytes,
    media_type~ : String,
    provider_options~ : Map[String, Json]
  )
  VideoV4Url(
    url~ : String,
    media_type~ : String?,
    provider_options~ : Map[String, Json]
  )
} derive(Debug, Eq)

///|
/// Construct an inline Base64 video input.
pub fn VideoModelV4File::base64(
  data~ : String,
  media_type~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> VideoModelV4File {
  VideoV4Data(data~, media_type~, provider_options~)
}

///|
/// Construct a binary video input.
pub fn VideoModelV4File::bytes(
  data~ : Bytes,
  media_type~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> VideoModelV4File {
  VideoV4Bytes(data~, media_type~, provider_options~)
}

///|
/// Construct a URL-backed video input.
pub fn VideoModelV4File::url(
  url : String,
  media_type? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> VideoModelV4File {
  VideoV4Url(url~, media_type~, provider_options~)
}

///|
/// The semantic role of a first/last frame input.
pub(all) enum VideoModelV4FrameType {
  VideoV4FirstFrame
  VideoV4LastFrame
} derive(Debug, Eq)

///|
/// A frame image paired with its semantic role.
pub(all) struct VideoModelV4FrameImage {
  image : VideoModelV4File
  frame_type : VideoModelV4FrameType
} derive(Debug, Eq)

///|
/// Construct a role-tagged frame image.
pub fn VideoModelV4FrameImage::new(
  image : VideoModelV4File,
  frame_type : VideoModelV4FrameType,
) -> VideoModelV4FrameImage {
  { image, frame_type }
}

///|
/// Construct a first-frame descriptor.
pub fn VideoModelV4FrameImage::first(
  image : VideoModelV4File,
) -> VideoModelV4FrameImage {
  { image, frame_type: VideoV4FirstFrame }
}

///|
/// Construct a last-frame descriptor.
pub fn VideoModelV4FrameImage::last(
  image : VideoModelV4File,
) -> VideoModelV4FrameImage {
  { image, frame_type: VideoV4LastFrame }
}

///|
/// Provider-neutral options passed to `VideoModelV4::do_generate`.
pub(all) struct VideoModelV4CallOptions {
  prompt : String?
  n : Int
  aspect_ratio : String?
  resolution : String?
  duration : Double?
  fps : Int?
  seed : Int?
  image : VideoModelV4File?
  frame_images : Array[VideoModelV4FrameImage]?
  input_references : Array[VideoModelV4File]?
  generate_audio : Bool?
  provider_options : Map[String, Json]
  headers : Map[String, String]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct V4 video generation options.
pub fn VideoModelV4CallOptions::new(
  prompt? : String,
  n? : Int = 1,
  aspect_ratio? : String,
  resolution? : String,
  duration? : Double,
  fps? : Int,
  seed? : Int,
  image? : VideoModelV4File,
  frame_images? : Array[VideoModelV4FrameImage],
  input_references? : Array[VideoModelV4File],
  generate_audio? : Bool,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoModelV4CallOptions {
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
    provider_options,
    headers,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Generated video data returned by a V4 provider.
pub(all) enum VideoModelV4VideoData {
  VideoV4Url(url~ : String, media_type~ : String)
  VideoV4Base64(data~ : String, media_type~ : String)
  VideoV4Binary(data~ : Bytes, media_type~ : String)
} derive(Debug, Eq)

///|
/// Result of one V4 video model call.
pub(all) struct VideoModelV4Result {
  videos : Array[VideoModelV4VideoData]
  warnings : Array[Warning]
  provider_metadata : Map[String, Json]
  request : RequestMetadata?
  response : ResponseMetadata?
} derive(Debug, Eq)

///|
/// Construct a V4 result.
pub fn VideoModelV4Result::new(
  videos : Array[VideoModelV4VideoData],
  warnings? : Array[Warning] = [],
  provider_metadata? : Map[String, Json] = Map([]),
  request? : RequestMetadata,
  response? : ResponseMetadata,
) -> VideoModelV4Result {
  {
    videos,
    warnings: copy_warnings(warnings),
    provider_metadata: copy_provider_metadata(provider_metadata),
    request,
    response,
  }
}

///|
/// Convert the existing protocol response at an explicit wire boundary.
pub fn VideoModelV4Result::from_video_response(
  response : VideoResponse,
) -> VideoModelV4Result {
  VideoModelV4Result::new(
    [
      for video in response.videos => {
        match video.data {
          GeneratedVideoData::Url(value) =>
            VideoV4Url(url=value, media_type=video.media_type)
          GeneratedVideoData::Base64(value) =>
            VideoV4Base64(data=value, media_type=video.media_type)
          GeneratedVideoData::Binary(value) =>
            VideoV4Binary(data=value, media_type=video.media_type)
        }
      }
    ],
    warnings=response.warnings,
    provider_metadata=response.provider_metadata,
    request?=response.request,
    response?=response.response,
  )
}

///|
/// Convert a V4 result back to the existing response shape used by protocol
/// implementations during migration.
pub fn VideoModelV4Result::to_video_response(
  self : VideoModelV4Result,
) -> VideoResponse {
  VideoResponse::new(
    [
      for video in self.videos => {
        match video {
          VideoV4Url(url~, media_type~) =>
            GeneratedVideo::new(GeneratedVideoData::Url(url), media_type)
          VideoV4Base64(data~, media_type~) =>
            GeneratedVideo::new(GeneratedVideoData::Base64(data), media_type)
          VideoV4Binary(data~, media_type~) =>
            GeneratedVideo::new(GeneratedVideoData::Binary(data), media_type)
        }
      }
    ],
  ).with_diagnostics(
    self.request,
    self.response,
    self.provider_metadata,
    self.warnings,
  )
}

///|
/// Convert V4 file input to the current provider wire input.
pub fn VideoModelV4File::to_video_input(self : VideoModelV4File) -> VideoInput {
  match self {
    VideoV4Data(data~, media_type~, ..) =>
      VideoInput::base64(data~, media_type~)
    VideoV4Bytes(data~, media_type~, ..) =>
      VideoInput::base64(data=@base64.encode(data), media_type~)
    VideoV4Url(url~, media_type~, ..) => VideoInput::url(url, media_type?)
  }
}

///|
/// Convert the current wire input to the V4 file representation.
pub fn VideoModelV4File::from_video_input(
  input : VideoInput,
) -> VideoModelV4File {
  match input {
    Url(url~, media_type~) =>
      VideoV4Url(url~, media_type~, provider_options=Map([]))
    Base64(data~, media_type~) =>
      VideoV4Data(data~, media_type~, provider_options=Map([]))
  }
}

///|
/// Convert V4 frame inputs to the current provider wire input.
pub fn VideoModelV4FrameImage::to_video_frame(
  self : VideoModelV4FrameImage,
) -> VideoFrameImage {
  let frame_type = match self.frame_type {
    VideoV4FirstFrame => FirstFrame
    VideoV4LastFrame => LastFrame
  }
  VideoFrameImage::new(self.image.to_video_input(), frame_type)
}

///|
/// Convert a wire frame descriptor to the V4 representation.
pub fn VideoModelV4FrameImage::from_video_frame_image(
  frame : VideoFrameImage,
) -> VideoModelV4FrameImage {
  let frame_type = match frame.frame_type {
    FirstFrame => VideoV4FirstFrame
    LastFrame => VideoV4LastFrame
  }
  { image: VideoModelV4File::from_video_input(frame.image), frame_type }
}

///|
/// Convert V4 options at the explicit protocol adapter boundary.
pub fn VideoModelV4CallOptions::to_video_call_options(
  self : VideoModelV4CallOptions,
) -> VideoCallOptions {
  VideoCallOptions::new(
    self.prompt.unwrap_or(""),
    n=self.n,
    aspect_ratio?=self.aspect_ratio,
    resolution?=self.resolution,
    duration?=self.duration,
    fps?=self.fps,
    seed?=self.seed,
    image?=match self.image {
      Some(value) => Some(value.to_video_input())
      None => None
    },
    frame_images=[
      for value in self.frame_images.unwrap_or([]) => value.to_video_frame()
    ],
    input_references=[
      for value in self.input_references.unwrap_or([]) => value.to_video_input()
    ],
    generate_audio?=self.generate_audio,
    headers=self.headers,
    provider_options=self.provider_options,
    retry_policy=self.retry_policy,
    cancellation_token?=self.cancellation_token,
  )
}

///|
/// Versioned provider contract for video generation.
pub(open) trait VideoModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_videos_per_call(Self) -> Int?
  async fn do_generate(Self, VideoModelV4CallOptions) -> VideoModelV4Result
}

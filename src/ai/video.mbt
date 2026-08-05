///|
/// Generate one or more videos, splitting calls at the provider model limit.
pub async fn generate_video(
  model : &VideoModelV4,
  prompt : String,
  n? : Int = 1,
  aspect_ratio? : String,
  resolution? : String,
  duration? : Double,
  fps? : Int,
  seed? : Int,
  image? : VideoModelV4File,
  frame_images? : Array[VideoModelV4FrameImage] = [],
  input_references? : Array[VideoModelV4File] = [],
  generate_audio? : Bool,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoModelV4Result {
  check_cancellation(cancellation_token)
  guard n > 0 else { fail("generate_video requires n to be greater than zero") }
  let max_videos_per_call = model.max_videos_per_call().unwrap_or(1)
  guard max_videos_per_call > 0 else {
    fail("video model max_videos_per_call must be greater than zero")
  }
  let videos : Array[VideoModelV4VideoData] = []
  let warnings : Array[Warning] = []
  let mut first_request : RequestMetadata? = None
  let mut response_metadata : ResponseMetadata? = None
  let mut provider_metadata : Map[String, Json] = Map([])
  let mut remaining = n
  while remaining > 0 {
    check_cancellation(cancellation_token)
    let batch_size = if remaining < max_videos_per_call {
      remaining
    } else {
      max_videos_per_call
    }
    let response = model.do_generate(
      VideoModelV4CallOptions::new(
        prompt~,
        n=batch_size,
        aspect_ratio?,
        resolution?,
        duration?,
        fps?,
        seed?,
        image?,
        frame_images=[ for value in frame_images => value ],
        input_references=[ for value in input_references => value ],
        generate_audio?,
        headers~,
        provider_options~,
        retry_policy~,
        cancellation_token?,
      ),
    )
    guard response.videos.length() == batch_size else {
      fail(
        "video provider returned {response.videos.length()} videos for a batch of {batch_size}",
      )
    }
    for video in response.videos {
      videos.push(video)
    }
    if first_request is None {
      first_request = response.request
    }
    response_metadata = merge_optional_response_metadata(
      response_metadata,
      response.response,
    )
    provider_metadata = merge_provider_metadata(
      provider_metadata,
      response.provider_metadata,
    )
    for warning in response.warnings {
      warnings.push(warning)
    }
    remaining = remaining - batch_size
  }
  VideoModelV4Result::new(
    videos,
    warnings~,
    provider_metadata~,
    request?=first_request,
    response?=response_metadata,
  )
}

///|
/// AI SDK-style camel-case spelling for `generate_video`.
pub async fn generateVideo(
  model : &VideoModelV4,
  prompt : String,
  n? : Int = 1,
  aspect_ratio? : String,
  resolution? : String,
  duration? : Double,
  fps? : Int,
  seed? : Int,
  image? : VideoModelV4File,
  frame_images? : Array[VideoModelV4FrameImage] = [],
  input_references? : Array[VideoModelV4File] = [],
  generate_audio? : Bool,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoModelV4Result {
  generate_video(
    model,
    prompt,
    n~,
    aspect_ratio?,
    resolution?,
    duration?,
    fps?,
    seed?,
    image?,
    frame_images~,
    input_references~,
    generate_audio?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

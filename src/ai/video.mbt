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

///|
/// Submit an asynchronous video generation operation without waiting for
/// completion.
///
/// Poll the returned `operation_id` with `get_video_status`, or observe
/// completion out of band through the provider's webhook delivery.
pub async fn start_video(
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
  webhook_url? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoModelV4OperationStartResult {
  guard n > 0 else { fail("start_video requires n to be greater than zero") }
  model.do_start(
    VideoModelV4CallOptions::new(
      prompt~,
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
      webhook_url?,
      provider_options~,
      headers~,
      retry_policy~,
      cancellation_token?,
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `start_video`.
pub async fn startVideo(
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
  webhook_url? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoModelV4OperationStartResult {
  start_video(
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
    webhook_url?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// Poll one asynchronous video operation once.
///
/// Raises `UnsupportedFunctionalityError` when the provider model does not
/// expose asynchronous operations.
pub async fn get_video_status(
  model : &VideoModelV4,
  operation_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoModelV4OperationStatusResult {
  guard operation_id.trim() != "" else {
    fail("get_video_status requires a non-empty operation_id")
  }
  model.do_status(
    VideoModelV4OperationStatusCallOptions::new(
      operation_id~,
      provider_options~,
      headers~,
      retry_policy~,
      cancellation_token?,
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `get_video_status`.
pub async fn getVideoStatus(
  model : &VideoModelV4,
  operation_id~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> VideoModelV4OperationStatusResult {
  get_video_status(
    model,
    operation_id~,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

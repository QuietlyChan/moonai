///|
/// KlingAI video model ids, e.g. `kling-v2-master` (the provider routes
/// text-to-video vs image-to-video by request shape rather than model id).
pub type KlingaiVideoModelId = String

///|
/// The KlingAI video model: asynchronous operations against
/// /v1/videos/{text2video,image2video,multi-image2video} with task polling.
struct KlingaiVideoModel {
  provider_name : String
  auth_token : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn klingai_video_value(
  model_id : KlingaiVideoModelId,
  auth_token~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> KlingaiVideoModel {
  {
    provider_name: "klingai.video",
    auth_token,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn KlingaiVideoModel::klingai_video_request_headers(
  self : KlingaiVideoModel,
  extra~ : Map[String, String],
) -> Map[String, String] {
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          ("Content-Type", "application/json"),
          ("Authorization", "Bearer \{self.auth_token}"),
        ]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Pick the endpoint family: image input chooses image2video, frame images
/// choose multi-image2video, otherwise text2video.
fn klingai_video_endpoint(
  options : @provider.VideoModelV4CallOptions,
) -> String {
  if options.frame_images is Some(images) && images.length() > 0 {
    "/v1/videos/multi-image2video"
  } else if options.image is Some(_) {
    "/v1/videos/image2video"
  } else {
    "/v1/videos/text2video"
  }
}

///|
/// Build the generation request body. The model name and prompt ride on
/// input; duration lives on output when given.
fn klingai_video_request_body(
  model_id : String,
  options : @provider.VideoModelV4CallOptions,
  resolution_values : Map[String, Json],
) -> Json {
  let input : Map[String, Json] = Map([("model_name", Json::string(model_id))])
  if options.prompt is Some(value) {
    input["prompt"] = Json::string(value)
  }
  if options.duration is Some(value) {
    input["duration"] = Json::number(value)
  }
  if options.aspect_ratio is Some(value) {
    input["aspect_ratio"] = Json::string(value)
  }
  match options.image {
    Some(file) =>
      match file {
        @provider.VideoV4Url(url~, ..) => input["image"] = Json::string(url)
        @provider.VideoV4Data(data~, media_type~, ..) =>
          input["image"] = Json::string("data:\{media_type};base64,\{data}")
        @provider.VideoV4Bytes(data~, media_type~, ..) => {
          let encoded = @base64.encode(data, padding=true)
          input["image"] = Json::string("data:\{media_type};base64,\{encoded}")
        }
      }
    None => ()
  }
  match options.frame_images {
    Some(images) if images.length() > 0 => {
      let frames : Array[Json] = []
      for frame in images {
        match frame.image {
          @provider.VideoV4Url(url~, ..) => frames.push(Json::string(url))
          @provider.VideoV4Data(data~, media_type~, ..) =>
            frames.push(Json::string("data:\{media_type};base64,\{data}"))
          @provider.VideoV4Bytes(data~, media_type~, ..) => {
            let encoded = @base64.encode(data, padding=true)
            frames.push(Json::string("data:\{media_type};base64,\{encoded}"))
          }
        }
      }
      input["image_list"] = Json::array(frames)
    }
    _ => ()
  }
  for entry in resolution_values.iter2() {
    input[entry.0] = entry.1
  }
  let fields : Map[String, Json] = Map([("input", Json::object(input))])
  if options.n > 1 {
    fields["n"] = Json::number(options.n.to_double())
  }
  Json::object(fields)
}

///|
fn decode_klingai_task_start(value : Json) -> String raise {
  match value {
    { "data": { "task_id": String(task_id), .. }, .. } => task_id
    _ => fail("klingai video start response missing data.task_id")
  }
}

///|
/// Map a task-status payload onto the V4 operation state plus, on success,
/// the resulting videos.
fn decode_klingai_task_status(
  value : Json,
) -> (
  @provider.VideoModelV4OperationState,
  Array[@provider.VideoModelV4VideoData],
  String?,
) raise {
  match value {
    { "data": { "task_status": String(status), .. }, .. } => {
      let state = match status {
        "submitted" => @provider.OperationSubmitted
        "processing" => @provider.OperationRunning
        "succeed" => @provider.OperationSucceeded
        "failed" => @provider.OperationFailed
        _ => @provider.OperationRunning
      }
      let videos : Array[@provider.VideoModelV4VideoData] = []
      let mut failure_message : String? = None
      if value
        is { "data": { "task_result": { "videos": Array(items), .. }, .. }, .. } {
        for item in items {
          if item is { "url": String(url), .. } {
            videos.push(@provider.VideoV4Url(url~, media_type="video/mp4"))
          }
        }
      }
      if value is { "data": { "task_status_msg": String(message), .. }, .. } {
        failure_message = Some(message)
      }
      (state, videos, failure_message)
    }
    _ => fail("klingai video status response missing data.task_status")
  }
}

///|
pub impl @provider.VideoModelV4 for KlingaiVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.VideoModelV4 for KlingaiVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoModelV4 for KlingaiVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoModelV4 for KlingaiVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  None
}

///|
pub impl @provider.VideoModelV4 for KlingaiVideoModel with fn do_generate(
  self,
  options,
) {
  let start = (self as &@provider.VideoModelV4).do_start(options)
  let cancellation_token = options.cancellation_token
  for ;; {
    @provider.check_cancellation(cancellation_token)
    let status = (self as &@provider.VideoModelV4).do_status(
      @provider.VideoModelV4OperationStatusCallOptions::new(
        operation_id=start.operation_id,
        headers=@provider_utils.copy_headers(options.headers),
        retry_policy=options.retry_policy,
        cancellation_token?,
      ),
    )
    match status.state {
      @provider.OperationSucceeded =>
        return status.result.unwrap_or(@provider.VideoModelV4Result::new([]))
      @provider.OperationFailed => fail("klingai video generation failed")
      _ => @provider_utils.sleep_with_cancellation(2000, cancellation_token)
    }
  }
}

///|
pub impl @provider.VideoModelV4 for KlingaiVideoModel with fn do_start(
  self,
  options,
) -> @provider.VideoModelV4OperationStartResult raise {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["klingai"],
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url="\{self.base_url}\{klingai_video_endpoint(options)}",
    headers=self.klingai_video_request_headers(extra=options.headers),
    body=klingai_video_request_body(self.model_id, options, resolution.values),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=klingai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let task_id = @provider_utils.handle_json_response(
    response, decode_klingai_task_start,
  )
  // The operation id carries the polling path so status hits the same
  // endpoint family the task was created on.
  @provider.VideoModelV4OperationStartResult::new(
    operation_id="\{klingai_video_endpoint(options)}/\{task_id}",
    state=@provider.OperationSubmitted,
  )
}

///|
pub impl @provider.VideoModelV4 for KlingaiVideoModel with fn do_status(
  self,
  call_options,
) -> @provider.VideoModelV4OperationStatusResult raise {
  let cancellation_token = call_options.cancellation_token
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url="\{self.base_url}\{call_options.operation_id}",
    headers=self.klingai_video_request_headers(extra=call_options.headers),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=klingai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (state, videos, failure_message) = @provider_utils.handle_json_response(
    response, decode_klingai_task_status,
  )
  let result = if state is @provider.OperationSucceeded && videos.length() > 0 {
    Some(@provider.VideoModelV4Result::new(videos))
  } else {
    None
  }
  let provider_metadata : Map[String, Json] = match failure_message {
    Some(message) =>
      Map([("klingai", { "taskStatusMsg": Json::string(message) })])
    None => Map([])
  }
  @provider.VideoModelV4OperationStatusResult::new(
    operation_id=call_options.operation_id,
    state~,
    result?,
    provider_metadata~,
  )
}

///|
fn klingai_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

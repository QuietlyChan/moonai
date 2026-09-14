///|
/// xAI video model ids (e.g. `grok-imagine-video`, `grok-imagine-video-1.5`).
pub type XaiVideoModelId = String

///|
/// The xAI video model: POST /videos/generations returns a request id; GET
/// /videos/{id} reports status and the finished video URL.
struct XaiVideoModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn xai_video_value(
  model_id : XaiVideoModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> XaiVideoModel {
  {
    provider_name: "xai.video",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn XaiVideoModel::video_headers(
  self : XaiVideoModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="XAI_API_KEY",
    description="xAI",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          ("Authorization", "Bearer \{api_key}"),
          ("Content-Type", "application/json"),
        ]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the generation request body.
fn xai_video_request_body(
  prompt~ : String?,
  duration~ : Double?,
  aspect_ratio~ : String?,
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([])
  if prompt is Some(value) {
    fields["prompt"] = Json::string(value)
  }
  if duration is Some(value) {
    fields["duration"] = Json::number(value)
  }
  if aspect_ratio is Some(value) {
    fields["aspect_ratio"] = Json::string(value)
  }
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
fn decode_xai_video_request_id(value : Json) -> String raise {
  match value {
    { "request_id": String(id), .. } => id
    _ => fail("xai video submit response missing request_id")
  }
}

///|
/// Map a status payload onto (state, video url).
fn decode_xai_video_status(
  value : Json,
) -> (@provider.VideoModelV4OperationState, String?) raise {
  match value {
    { "status": String(status), .. } => {
      let url = match value {
        { "video": { "url": String(video_url), .. }, .. } => Some(video_url)
        _ => None
      }
      let state = match status {
        "ready" => @provider.OperationSucceeded
        "expired" | "failed" => @provider.OperationFailed
        _ => @provider.OperationRunning
      }
      (state, url)
    }
    _ => fail("xai video status response missing status")
  }
}

///|
pub impl @provider.VideoModelV4 for XaiVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.VideoModelV4 for XaiVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoModelV4 for XaiVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoModelV4 for XaiVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.VideoModelV4 for XaiVideoModel with fn do_generate(
  self,
  options,
) {
  let start = (self as &@provider.VideoModelV4).do_start(options)
  let cancellation_token = options.cancellation_token
  let poll_started_at = @env.now()
  for ;; {
    @provider.check_cancellation(cancellation_token)
    @provider_utils.sleep_with_cancellation(3000, cancellation_token)
    if @env.now() - poll_started_at > 600_000UL {
      fail("xai video polling exceeded 600000ms")
    }
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
      @provider.OperationFailed => fail("xai video generation failed")
      _ => ()
    }
  }
}

///|
pub impl @provider.VideoModelV4 for XaiVideoModel with fn do_start(
  self,
  options,
) -> @provider.VideoModelV4OperationStartResult raise {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["xai"],
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/videos/generations"),
    headers=self.video_headers(extra=options.headers),
    body=xai_video_request_body(
      prompt=options.prompt,
      duration=options.duration,
      aspect_ratio=options.aspect_ratio,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=xai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let request_id = @provider_utils.handle_json_response(
    response, decode_xai_video_request_id,
  )
  @provider.VideoModelV4OperationStartResult::new(
    operation_id=request_id,
    state=@provider.OperationSubmitted,
  )
}

///|
pub impl @provider.VideoModelV4 for XaiVideoModel with fn do_status(
  self,
  call_options,
) -> @provider.VideoModelV4OperationStatusResult raise {
  let cancellation_token = call_options.cancellation_token
  let poll_response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(
      self.base_url,
      "/videos/\{call_options.operation_id}",
    ),
    headers=self.video_headers(extra=call_options.headers),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=xai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (state, url) = @provider_utils.handle_json_response(
    poll_response, decode_xai_video_status,
  )
  let result = if state is @provider.OperationSucceeded {
    let videos : Array[@provider.VideoModelV4VideoData] = match url {
      Some(video_url) =>
        [
          @provider.VideoModelV4VideoData::VideoV4Url(
            url=video_url,
            media_type="video/mp4",
          ),
        ]
      None => []
    }
    Some(@provider.VideoModelV4Result::new(videos))
  } else {
    None
  }
  @provider.VideoModelV4OperationStatusResult::new(
    operation_id=call_options.operation_id,
    state~,
    result?,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      poll_response.value,
      self.provider_name,
    ),
  )
}

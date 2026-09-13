///|
/// The Black Forest Labs video model: same queue protocol as the image
/// model — POST /{model}, then poll the returned polling_url until the
/// status is Ready; result.sample carries the video URL.
struct BflVideoModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  poll_interval_ms : Int
  poll_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn bfl_video_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  poll_interval_ms~ : Int,
  poll_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> BflVideoModel {
  {
    provider_name: "bfl.video",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    poll_interval_ms,
    poll_timeout_ms,
    http_transport,
  }
}

///|
fn BflVideoModel::video_headers(
  self : BflVideoModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="BFL_API_KEY",
    description="Black Forest Labs",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([("x-key", api_key), ("Content-Type", "application/json")]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the video submit body: prompt, optional duration/aspect ratio,
/// plus any bfl namespace passthrough.
fn bfl_video_request_body(
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
fn decode_bfl_video_submit(value : Json) -> String raise {
  match value {
    { "id": String(id), .. } => id
    _ => fail("bfl video submit response missing id")
  }
}

///|
/// A Ready poll response carries the sample video URL.
fn decode_bfl_video_poll(value : Json) -> (String, String?) raise {
  match value {
    { "status": String(status), .. } => {
      let sample = match value {
        { "result": { "sample": String(url), .. }, .. } => Some(url)
        _ => None
      }
      (status, sample)
    }
    _ => fail("bfl video poll response missing status")
  }
}

///|
pub impl @provider.VideoModelV4 for BflVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.VideoModelV4 for BflVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoModelV4 for BflVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoModelV4 for BflVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.VideoModelV4 for BflVideoModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["bfl"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let start = (self as &@provider.VideoModelV4).do_start(options)
  let poll_url = match start.provider_metadata.get("pollingUrl") {
    Some(Json::String(url)) => url
    _ => "https://api.bfl.ai/v1/get_result?id=\{start.operation_id}"
  }
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let poll_started_at = @env.now()
  let mut sample_url : String? = None
  let mut succeeded = false
  let mut last_poll : @provider_utils.JsonHttpResponse? = None
  for ;; {
    @provider.check_cancellation(cancellation_token)
    @provider_utils.sleep_with_cancellation(
      self.poll_interval_ms,
      cancellation_token,
    )
    if @env.now() - poll_started_at > self.poll_timeout_ms.to_uint64() {
      fail("bfl video polling exceeded \{self.poll_timeout_ms}ms")
    }
    let poll_response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url=poll_url,
      headers=self.video_headers(extra=options.headers),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=bfl_error_to_message,
      is_retryable_response=(_status_code, _error) => None,
      transport=self.http_transport,
    )
    let (status, sample) = @provider_utils.handle_json_response(
      poll_response, decode_bfl_video_poll,
    )
    last_poll = Some(poll_response)
    if status == "Ready" {
      sample_url = sample
      succeeded = true
      break
    }
    if status == "Error" || status == "Content Moderated" {
      fail("bfl video generation failed with status \{status}")
    }
  }
  guard succeeded else { fail("bfl video generation did not complete") }
  let videos = match sample_url {
    Some(url) =>
      [
        @provider.VideoModelV4VideoData::VideoV4Url(
          url~,
          media_type="video/mp4",
        ),
      ]
    None => []
  }
  @provider.VideoModelV4Result::new(
    videos,
    warnings~,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      match last_poll {
        Some(poll) => poll.value
        None => Json::object(Map([]))
      },
      self.provider_name,
    ),
    response=@provider.ResponseMetadata::new(
      model_id=self.model_id,
      created_at=request_created_at,
    ),
  )
}

///|
pub impl @provider.VideoModelV4 for BflVideoModel with fn do_start(
  self,
  options,
) -> @provider.VideoModelV4OperationStartResult raise {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["bfl"],
  )
  let cancellation_token = options.cancellation_token
  let submit_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, self.model_id),
    headers=self.video_headers(extra=options.headers),
    body=bfl_video_request_body(
      prompt=options.prompt,
      duration=options.duration,
      aspect_ratio=options.aspect_ratio,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=bfl_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let job_id = @provider_utils.handle_json_response(
    submit_response, decode_bfl_video_submit,
  )
  let polling_url = match submit_response.value {
    { "polling_url": String(url), .. } => url
    _ => "https://api.bfl.ai/v1/get_result?id=\{job_id}"
  }
  @provider.VideoModelV4OperationStartResult::new(
    operation_id=job_id,
    state=@provider.OperationSubmitted,
    provider_metadata=Map([("pollingUrl", Json::string(polling_url))]),
  )
}

///|
pub impl @provider.VideoModelV4 for BflVideoModel with fn do_status(
  self,
  call_options,
) -> @provider.VideoModelV4OperationStatusResult raise {
  let polling_url = "https://api.bfl.ai/v1/get_result?id=\{call_options.operation_id}"
  let cancellation_token = call_options.cancellation_token
  let poll_response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=polling_url,
    headers=self.video_headers(extra=call_options.headers),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=bfl_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (status, sample) = @provider_utils.handle_json_response(
    poll_response, decode_bfl_video_poll,
  )
  let state = match status {
    "Ready" => @provider.OperationSucceeded
    "Error" | "Content Moderated" => @provider.OperationFailed
    _ => @provider.OperationRunning
  }
  let result = if state is @provider.OperationSucceeded {
    sample.map(url => {
      @provider.VideoModelV4Result::new([
        @provider.VideoV4Url(url~, media_type="video/mp4"),
      ])
    })
  } else {
    None
  }
  @provider.VideoModelV4OperationStatusResult::new(
    operation_id=call_options.operation_id,
    state~,
    result?,
  )
}

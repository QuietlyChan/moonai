///|
/// Google video model ids (Veo family, e.g. `veo-3.0-generate-001`).
pub type GoogleVideoModelId = String

///|
/// The Google video model: Veo's predictLongRunning protocol — submit to
/// /models/{model}:predictLongRunning, then poll the returned operation
/// name until done; generatedSamples[].video.uri carries the video.
struct GoogleVideoModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int32
  poll_interval_ms : Int32
  poll_timeout_ms : Int32
  http_transport : &@provider_utils.HttpTransport
}

///|
fn google_video_value(
  model_id : GoogleVideoModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int32,
  poll_interval_ms~ : Int32,
  poll_timeout_ms~ : Int32,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GoogleVideoModel {
  {
    provider_name: "google.video",
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
fn GoogleVideoModel::google_video_api_headers(
  self : GoogleVideoModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          (
            "x-goog-api-key",
            @provider_utils.load_api_key(
              self.api_key,
              environment_variable_name="GOOGLE_GENERATIVE_AI_API_KEY",
              description="Google Gemini",
            ),
          ),
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
/// Build the predictLongRunning body: one instance with the prompt and the
/// parameters block (sampleCount / aspectRatio).
fn google_video_request_body(
  prompt~ : String?,
  n~ : Int32,
  aspect_ratio~ : String?,
  provider_options~ : Map[String, Json],
) -> Json {
  let instance : Map[String, Json] = Map([])
  if prompt is Some(value) {
    instance["prompt"] = Json::string(value)
  }
  let parameters : Map[String, Json] = Map([
    ("sampleCount", Json::number(n.to_double())),
  ])
  if aspect_ratio is Some(value) {
    parameters["aspectRatio"] = Json::string(value)
  }
  for entry in provider_options.iter2() {
    parameters[entry.0] = entry.1
  }
  let outer : Map[String, Json] = Map([
    ("instances", Json::array([Json::object(instance)])),
    ("parameters", Json::object(parameters)),
  ])
  Json::object(outer)
}

///|
fn decode_google_operation_name(value : Json) -> String raise {
  match value {
    { "name": String(name), .. } => name
    _ => fail("google video operation response missing name")
  }
}

///|
/// Map a finished operation onto the video URL
/// (response.generateVideoResponse.generatedSamples[].video.uri).
fn decode_google_operation_status(
  value : Json,
) -> (@provider.VideoModelV4OperationState, String?) raise {
  match value {
    { "done": True, .. } => {
      let error_message = match value {
        { "error": { "message": String(message), .. }, .. } => Some(message)
        _ => None
      }
      guard error_message is None else {
        let message = error_message.unwrap_or("")
        fail("google video generation failed: \{message}")
      }
      let sample_url = match value {
        {
          "response": {
            "generateVideoResponse": { "generatedSamples": Array(samples), .. },
            ..
          },
          ..
        } =>
          match samples.get(0) {
            Some({ "video": { "uri": String(uri), .. }, .. }) => Some(uri)
            _ => None
          }
        _ => None
      }
      (@provider.OperationSucceeded, sample_url)
    }
    { "done": False, .. } | { "error": Object(_), .. } =>
      (@provider.OperationRunning, None)
    _ => (@provider.OperationRunning, None)
  }
}

///|
pub impl @provider.VideoModelV4 for GoogleVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.VideoModelV4 for GoogleVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoModelV4 for GoogleVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoModelV4 for GoogleVideoModel with fn max_videos_per_call(
  _self,
) -> Int32? {
  None
}

///|
pub impl @provider.VideoModelV4 for GoogleVideoModel with fn do_generate(
  self,
  options,
) {
  let start = (self as &@provider.VideoModelV4).do_start(options)
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let poll_started_at = @env.now()
  let mut video_url : String? = None
  let mut succeeded = false
  for ;; {
    @provider.check_cancellation(cancellation_token)
    @provider_utils.sleep_with_cancellation(
      self.poll_interval_ms,
      cancellation_token,
    )
    if @env.now() - poll_started_at > self.poll_timeout_ms.to_uint64() {
      fail("google video polling exceeded \{self.poll_timeout_ms}ms")
    }
    let poll_response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url="\{self.base_url}/\{start.operation_id}",
      headers=self.google_video_api_headers(extra=options.headers),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=google_error_to_message,
      is_retryable_response=(_status_code, _error) => None,
      transport=self.http_transport,
    )
    let (state, url) = @provider_utils.handle_json_response(
      poll_response, decode_google_operation_status,
    )
    if state is @provider.OperationSucceeded {
      video_url = url
      succeeded = true
      break
    }
  }
  guard succeeded else { fail("google video generation did not complete") }
  let videos = match video_url {
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
    provider_metadata=@provider_utils.provider_metadata_from_json(
      Json::object(Map([])),
      self.provider_name,
    ),
    response=@provider.ResponseMetadata::new(
      model_id=self.model_id,
      created_at=request_created_at,
    ),
  )
}

///|
pub impl @provider.VideoModelV4 for GoogleVideoModel with fn do_start(
  self,
  options,
) -> @provider.VideoModelV4OperationStartResult raise {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["google"],
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url="\{self.base_url}/models/\{self.model_id}:predictLongRunning",
    headers=self.google_video_api_headers(extra=options.headers),
    body=google_video_request_body(
      prompt=options.prompt,
      n=options.n,
      aspect_ratio=options.aspect_ratio,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=google_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let operation_name = @provider_utils.handle_json_response(
    response, decode_google_operation_name,
  )
  @provider.VideoModelV4OperationStartResult::new(
    operation_id=operation_name,
    state=@provider.OperationSubmitted,
  )
}

///|
pub impl @provider.VideoModelV4 for GoogleVideoModel with fn do_status(
  self,
  call_options,
) -> @provider.VideoModelV4OperationStatusResult raise {
  let cancellation_token = call_options.cancellation_token
  let poll_response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url="\{self.base_url}/\{call_options.operation_id}",
    headers=self.google_video_api_headers(extra=call_options.headers),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=google_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (state, url) = @provider_utils.handle_json_response(
    poll_response, decode_google_operation_status,
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

///|
pub extend GoogleVideoModel with @provider.VideoModelV4::{
  specification_version,
  provider,
  model_id,
  max_videos_per_call,
  do_generate,
  do_start,
  do_status,
}

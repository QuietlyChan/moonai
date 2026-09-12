///|
/// AI SDK-aligned V4 surface for MiniMax's asynchronous video endpoint.
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn do_generate(
  self,
  options,
) {
  self.generate_video_v4(options)
}

///|
async fn MiniMaxVideoModel::start_video_v4(
  self : MiniMaxVideoModel,
  options : @provider.VideoModelV4CallOptions,
) -> @provider.VideoModelV4OperationStartResult {
  let (provider_options, option_warnings) = parse_minimax_video_options(
    options.provider_options,
  )
  let warnings = option_warnings
  let (body, _image_count, _reference_video_urls) = self.create_v4_body(
    options, provider_options, warnings,
  )
  // Forward the caller-owned callback endpoint; MiniMax expects the
  // receiver to echo its challenge handshake within three seconds.
  let body = match (body, options.webhook_url) {
    (Object(fields), Some(url)) => {
      fields["callback_url"] = Json::string(url)
      Json::object(fields)
    }
    _ => body
  }
  let create_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/v2/video_generation"),
    headers=self.request_headers_with(options.headers),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=minimax_video_error_message,
    validate_response=validate_minimax_create_video_response,
    transport=self.http_transport,
  )
  let task_id = match create_response.value {
    { "task_id": String(value), .. } if value != "" => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="No task_id returned from the MiniMax API. Response: " +
          create_response.value.stringify(),
        data=create_response.value,
      )
  }
  @provider.VideoModelV4OperationStartResult::new(
    operation_id=task_id,
    state=@provider.OperationSubmitted,
    provider_metadata=Map([
      ("minimax", Json::object(Map([("taskId", Json::string(task_id))]))),
    ]),
    warnings~,
  )
}

///|
async fn MiniMaxVideoModel::video_operation_status_v4(
  self : MiniMaxVideoModel,
  call_options : @provider.VideoModelV4OperationStatusCallOptions,
) -> @provider.VideoModelV4OperationStatusResult {
  let task_id = call_options.operation_id
  let response_value = self.minimax_protected_status_json(
      url=@provider_utils.append_path(
        self.base_url,
        "/v2/query/video_generation/" +
        @provider_utils.encode_path_segment(task_id),
      ),
      headers=self.request_headers_with(call_options.headers),
      retry_policy=call_options.retry_policy,
      cancellation_token=call_options.cancellation_token,
    ).0
  let status : String? = match response_value {
    { "task": { "status": String(value), .. }, .. } => Some(value)
    { "task": { "status": Null, .. }, .. } | { "task": { .. }, .. } => None
    _ =>
      raise @provider.InvalidResponseDataError(
        message="MiniMax video status response did not contain task",
        data=response_value,
      )
  }
  if status == Some("succeeded") {
    let video_url = match response_value {
      { "task": { "content": { "url": String(url), .. }, .. }, .. } if url != "" =>
        url
      _ =>
        raise @provider.InvalidResponseDataError(
          message="MiniMax video generation completed but no video URL was returned. Task ID: " +
            task_id,
          data=response_value,
        )
    }
    let provider_details : Map[String, Json] = Map([
      ("taskId", Json::string(task_id)),
      ("videoUrl", Json::string(video_url)),
      (
        "resolvedInputs",
        ({ "imageCount": 0, "referenceVideoUrls": Json::array([]) } : Json),
      ),
    ])
    let metadata : Map[String, Json] = Map([
      ("minimax", Json::object(provider_details)),
    ])
    let result = @provider.VideoModelV4Result::new(
      [@provider.VideoV4Url(url=video_url, media_type="video/mp4")],
      provider_metadata=metadata,
      request?=None,
      response=@provider.ResponseMetadata::new(
        model_id=self.model_id,
        created_at=(@env.now() / 1000UL).to_int(),
      ),
    )
    @provider.VideoModelV4OperationStatusResult::new(
      operation_id=task_id,
      state=@provider.OperationSucceeded,
      result~,
      provider_metadata=metadata,
    )
  } else if status == Some("failed") ||
    status == Some("cancelled") ||
    status == Some("expired") {
    @provider.VideoModelV4OperationStatusResult::new(
      operation_id=task_id,
      state=@provider.OperationFailed,
      provider_metadata=Map([
        ("minimax", Json::object(Map([("taskId", Json::string(task_id))]))),
      ]),
    )
  } else {
    @provider.VideoModelV4OperationStatusResult::new(
      operation_id=task_id,
      state=@provider.OperationRunning,
      provider_metadata=Map([
        ("minimax", Json::object(Map([("taskId", Json::string(task_id))]))),
      ]),
    )
  }
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn do_start(
  self,
  options,
) -> @provider.VideoModelV4OperationStartResult raise {
  self.start_video_v4(options)
}

///|

///|
/// Poll one MiniMax video status URL with protected redirect handling:
/// redirects away from the trusted API origin are validated per hop
/// (AI SDK #20124).
async fn MiniMaxVideoModel::minimax_protected_status_json(
  self : MiniMaxVideoModel,
  url~ : String,
  headers~ : Map[String, String],
  retry_policy~ : @provider.RetryPolicy,
  cancellation_token~ : @provider.CancellationToken?,
) -> (Json, @provider.ResponseMetadata?) {
  // Protected polling: redirects are manually followed and every hop away
  // from the trusted API origin is validated (AI SDK #20124).
  let response = @provider_utils.get_json_protected(
    provider_name=self.provider_name,
    url~,
    headers~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy~,
    cancellation_token?,
    error_to_message=minimax_video_error_message,
    validate_response=validate_minimax_video_status_response,
    trusted_origin=self.base_url,
    transport=self.http_transport,
  )
  (response.value, Some(response.response))
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn do_status(
  self,
  call_options,
) -> @provider.VideoModelV4OperationStatusResult raise {
  self.video_operation_status_v4(call_options)
}

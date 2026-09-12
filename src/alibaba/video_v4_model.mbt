///|
/// AI SDK-aligned V4 surface for Alibaba's asynchronous video endpoint.
impl @provider.VideoModelV4 for AlibabaVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.VideoModelV4 for AlibabaVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.VideoModelV4 for AlibabaVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
impl @provider.VideoModelV4 for AlibabaVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
impl @provider.VideoModelV4 for AlibabaVideoModel with fn do_generate(
  self,
  options,
) {
  self.generate_video_v4(options)
}

///|
async fn AlibabaVideoModel::start_video_v4(
  self : AlibabaVideoModel,
  options : @provider.VideoModelV4CallOptions,
) -> @provider.VideoModelV4OperationStartResult {
  let (provider_options, option_warnings) = parse_alibaba_video_options(
    options.provider_options,
  )
  let warnings = option_warnings
  let body = self.create_v4_body(options, provider_options, warnings)
  let create_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(
      self.base_url,
      "/api/v1/services/aigc/video-generation/video-synthesis",
    ),
    headers=self.request_headers_with(options.headers, true),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=alibaba_video_error_message,
    transport=self.http_transport,
  )
  let task_id = alibaba_video_task_id(create_response.value)
  @provider.VideoModelV4OperationStartResult::new(
    operation_id=task_id,
    state=@provider.OperationSubmitted,
    provider_metadata=Map([
      (
        "alibaba",
        alibaba_video_task_metadata(task_id, "", create_response.value),
      ),
    ]),
    warnings~,
  )
}

///|
async fn AlibabaVideoModel::video_operation_status_v4(
  self : AlibabaVideoModel,
  call_options : @provider.VideoModelV4OperationStatusCallOptions,
) -> @provider.VideoModelV4OperationStatusResult {
  let task_id = call_options.operation_id
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(
      self.base_url,
      "/api/v1/tasks/" + @provider_utils.encode_path_segment(task_id),
    ),
    headers=self.request_headers_with(call_options.headers, false),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?=call_options.cancellation_token,
    error_to_message=alibaba_video_error_message,
    transport=self.http_transport,
  )
  let status = alibaba_video_task_status(response.value)
  if status == "SUCCEEDED" {
    let video_url = alibaba_video_url(response.value)
    let result = alibaba_video_result(
      task_id,
      video_url,
      response.value,
      [],
      response.request,
      alibaba_video_response_metadata(
        self.model_id,
        (@env.now() / 1000UL).to_int(),
        response.response,
      ),
    )
    @provider.VideoModelV4OperationStatusResult::new(
      operation_id=task_id,
      state=@provider.OperationSucceeded,
      result~,
      provider_metadata=Map([
        (
          "alibaba",
          alibaba_video_task_metadata(task_id, video_url, response.value),
        ),
      ]),
    )
  } else if status == "FAILED" || status == "CANCELED" {
    @provider.VideoModelV4OperationStatusResult::new(
      operation_id=task_id,
      state=@provider.OperationFailed,
      provider_metadata=Map([
        ("alibaba", alibaba_video_task_metadata(task_id, "", response.value)),
      ]),
    )
  } else {
    @provider.VideoModelV4OperationStatusResult::new(
      operation_id=task_id,
      state=@provider.OperationRunning,
      provider_metadata=Map([
        ("alibaba", alibaba_video_task_metadata(task_id, "", response.value)),
      ]),
    )
  }
}

///|
impl @provider.VideoModelV4 for AlibabaVideoModel with fn do_start(
  self,
  options,
) -> @provider.VideoModelV4OperationStartResult raise {
  self.start_video_v4(options)
}

///|
impl @provider.VideoModelV4 for AlibabaVideoModel with fn do_status(
  self,
  call_options,
) -> @provider.VideoModelV4OperationStatusResult raise {
  self.video_operation_status_v4(call_options)
}

///|
/// Alibaba DashScope asynchronous video-generation model.
pub struct AlibabaVideoModel {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv model_id : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct an Alibaba asynchronous video model.
pub fn alibaba_video(
  model_id : AlibabaVideoModelId,
  api_key? : String = "",
  base_url? : String = "https://dashscope-intl.aliyuncs.com",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> AlibabaVideoModel {
  {
    provider_name: "alibaba.video",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    model_id,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
fn AlibabaVideoModel::request_headers(
  self : AlibabaVideoModel,
  options : @provider.VideoCallOptions,
  async_request : Bool,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_alibaba_api_key(self.api_key)}"
  if async_request {
    headers["X-DashScope-Async"] = "enable"
  }
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/alibaba/\{VERSION}"],
    ),
    options.headers,
  )
}

///|
fn alibaba_video_error_message(json : Json) -> String? {
  match json {
    { "message": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
/// Preserve the task fields exposed by DashScope's asynchronous video API in
/// the provider metadata returned by the high-level video helper.
fn alibaba_video_task_metadata(
  task_id : String,
  video_url : String,
  create_json : Json,
  final_json : Json,
  model_id : String,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("taskId", Json::string(task_id)),
    ("videoUrl", Json::string(video_url)),
    ("modelId", Json::string(model_id)),
  ])
  match create_json {
    { "request_id": String(value), .. } =>
      fields["createRequestId"] = Json::string(value)
    _ => ()
  }
  let metadata = match final_json {
    { "request_id": String(value), "output": output, .. } => {
      fields["requestId"] = Json::string(value)
      alibaba_video_output_metadata(output, fields)
    }
    { "output": output, .. } => alibaba_video_output_metadata(output, fields)
    _ => Json::object(fields)
  }
  match metadata {
    Object(values) => {
      alibaba_video_usage_metadata(final_json, values)
      Json::object(values)
    }
    _ => metadata
  }
}

///|
fn alibaba_video_output_metadata(
  output : Json,
  fields : Map[String, Json],
) -> Json {
  match output {
    Object(values) => {
      for
        pair in [
          ("task_status", "taskStatus"),
          ("submit_time", "submitTime"),
          ("scheduled_time", "scheduledTime"),
          ("end_time", "endTime"),
          ("orig_prompt", "originalPrompt"),
          ("actual_prompt", "actualPrompt"),
          ("code", "code"),
          ("message", "message"),
        ] {
        let wire_name = pair.0
        let metadata_name = pair.1
        match values.get(wire_name) {
          Some(value) => fields[metadata_name] = value
          None => ()
        }
      }
      match values.get("task_status") {
        Some(value) => fields["taskStatus"] = value
        None => ()
      }
      Json::object(fields)
    }
    _ => Json::object(fields)
  }
}

///|
fn alibaba_video_usage_metadata(
  final_json : Json,
  fields : Map[String, Json],
) -> Unit {
  match final_json {
    { "usage": Object(usage), .. } => {
      let usage_fields : Map[String, Json] = Map([])
      for
        pair in [
          ("duration", "duration"),
          ("output_video_duration", "outputVideoDuration"),
          ("SR", "resolution"),
          ("size", "size"),
        ] {
        let wire_name = pair.0
        let metadata_name = pair.1
        match usage.get(wire_name) {
          Some(value) => usage_fields[metadata_name] = value
          None => ()
        }
      }
      if usage_fields.length() > 0 {
        fields["usage"] = Json::object(usage_fields)
      }
    }
    _ => ()
  }
}

///|
fn alibaba_video_input_value(input : @provider.VideoInput) -> String {
  match input {
    @provider.Url(url~, ..) => url
    @provider.Base64(data~, ..) => data
  }
}

///|
fn alibaba_video_input_data_uri(input : @provider.VideoInput) -> String {
  match input {
    @provider.Url(url~, ..) => url
    @provider.Base64(data~, media_type~) =>
      "data:" + media_type + ";base64," + data
  }
}

///|
fn find_alibaba_frame(
  frames : Array[@provider.VideoFrameImage],
  frame_type : @provider.VideoFrameType,
) -> @provider.VideoInput? {
  for frame in frames {
    if frame.frame_type == frame_type {
      return Some(frame.image)
    }
  }
  None
}

///|
fn alibaba_reference_media_type(url : String, media_type : String?) -> String {
  match media_type {
    Some(value) if value.has_prefix("video/") => "reference_video"
    _ => {
      let normalized = url.to_lower()
      if normalized.contains(".mp4") || normalized.contains(".mov") {
        "reference_video"
      } else {
        "reference_image"
      }
    }
  }
}

///|
fn alibaba_video_mode(model_id : String) -> String {
  if model_id.contains("-i2v") {
    "i2v"
  } else if model_id.contains("-r2v") {
    "r2v"
  } else {
    "t2v"
  }
}

///|
fn is_wan27(model_id : String) -> Bool {
  model_id.has_prefix("wan2.7")
}

///|
fn resolution_tier(value : String) -> String {
  match value {
    "1280x720" | "720x1280" | "960x960" | "1088x832" | "832x1088" => "720P"
    "1920x1080" | "1080x1920" | "1440x1440" | "1632x1248" | "1248x1632" =>
      "1080P"
    "832x480" | "480x832" | "624x624" => "480P"
    _ => value
  }
}

///|
fn ratio_from_resolution(value : String) -> String? {
  let parts = value.split("x").collect()
  guard parts.length() == 2 else { return None }
  let width = @string.parse_int(parts[0]) catch { _ => return None }
  let height = @string.parse_int(parts[1]) catch { _ => return None }
  guard width > 0 && height > 0 else { return None }
  let mut a = width
  let mut b = height
  while b != 0 {
    let next = a % b
    a = b
    b = next
  }
  let ratio = (width / a).to_string() + ":" + (height / a).to_string()
  match ratio {
    "16:9" | "9:16" | "1:1" | "4:3" | "3:4" => Some(ratio)
    _ => None
  }
}

///|
fn AlibabaVideoModel::create_body(
  self : AlibabaVideoModel,
  options : @provider.VideoCallOptions,
  provider_options : AlibabaVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> Json {
  if options.n > 1 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="n",
        details="Alibaba video models only support generating 1 video per call.",
      ),
    )
  }
  let mode = alibaba_video_mode(self.model_id)
  let wan27 = is_wan27(self.model_id)
  let input : Map[String, Json] = Map([])
  if options.prompt != "" {
    input["prompt"] = Json::string(options.prompt)
  }
  match provider_options.negative_prompt {
    Some(value) => input["negative_prompt"] = Json::string(value)
    None => ()
  }
  match provider_options.audio_url {
    Some(value) => input["audio_url"] = Json::string(value)
    None => ()
  }
  let first_frame_image = find_alibaba_frame(
    options.frame_images,
    @provider.FirstFrame,
  )
  let first_frame = match first_frame_image {
    Some(value) => Some(value)
    None => options.image
  }
  let last_frame = find_alibaba_frame(options.frame_images, @provider.LastFrame)
  if mode == "i2v" {
    match first_frame {
      Some(value) =>
        input["img_url"] = Json::string(alibaba_video_input_value(value))
      None => ()
    }
  }
  if mode == "r2v" {
    if wan27 {
      let media : Array[Json] = []
      if provider_options.media.length() > 0 {
        for item in provider_options.media {
          let fields : Map[String, Json] = Map([
            ("type", Json::string(item.media_type)),
            ("url", Json::string(item.url)),
          ])
          match item.reference_voice {
            Some(value) => fields["reference_voice"] = Json::string(value)
            None => ()
          }
          media.push(Json::object(fields))
        }
      } else {
        for reference in options.input_references {
          match reference {
            @provider.Url(url~, media_type~) => {
              let kind = alibaba_reference_media_type(url, media_type)
              media.push({ "type": kind, "url": url })
            }
            @provider.Base64(media_type~, ..) =>
              if media_type.has_prefix("image/") {
                media.push({
                  "type": "reference_image",
                  "url": alibaba_video_input_data_uri(reference),
                })
              } else {
                warnings.push(
                  @provider.Warning::Unsupported(
                    feature="inputReferences",
                    details="Alibaba reference-to-video requires URL references for videos. The inline video reference was ignored.",
                  ),
                )
              }
          }
        }
        match first_frame_image {
          Some(value) =>
            media.push({
              "type": "first_frame",
              "url": alibaba_video_input_data_uri(value),
            })
          None => ()
        }
      }
      if media.length() > 0 {
        input["media"] = Json::array(media)
      }
    } else {
      let urls : Array[Json] = []
      if options.frame_images.length() == 0 &&
        options.input_references.length() > 0 {
        for reference in options.input_references {
          match reference {
            @provider.Url(url~, ..) => urls.push(Json::string(url))
            @provider.Base64(..) =>
              warnings.push(
                @provider.Warning::Unsupported(
                  feature="inputReferences",
                  details="Alibaba wan2.6 requires URL references; an inline reference was ignored.",
                ),
              )
          }
        }
      } else if options.frame_images.length() == 0 {
        for url in provider_options.reference_urls {
          urls.push(Json::string(url))
        }
      }
      if urls.length() > 0 {
        input["reference_urls"] = Json::array(urls)
      }
    }
  }
  if options.input_references.length() > 0 && mode != "r2v" {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="inputReferences",
        details="Alibaba only supports inputReferences on reference-to-video models; the references were ignored.",
      ),
    )
  }
  if last_frame is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="frameImages",
        details="Alibaba video models do not support last_frame; the last frame image was ignored.",
      ),
    )
  }
  let parameters : Map[String, Json] = Map([])
  match options.duration {
    Some(value) => parameters["duration"] = Json::number(value)
    None => ()
  }
  match options.seed {
    Some(value) => parameters["seed"] = Json::number(value.to_double())
    None => ()
  }
  match options.resolution {
    Some(value) if mode == "i2v" =>
      parameters["resolution"] = Json::string(resolution_tier(value))
    Some(value) if wan27 => {
      let tier = resolution_tier(value)
      if tier == "720P" || tier == "1080P" {
        parameters["resolution"] = Json::string(tier)
      } else {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="resolution",
            details="Alibaba wan2.7 models accept only 720P or 1080P; the requested resolution was ignored.",
          ),
        )
      }
    }
    Some(value) =>
      parameters["size"] = Json::string(value.replace(old="x", new="*"))
    None => ()
  }
  if wan27 && mode != "i2v" {
    let ratio = match provider_options.ratio {
      Some(value) => Some(value)
      None =>
        match options.aspect_ratio {
          Some(value) => Some(value)
          None =>
            match options.resolution {
              Some(value) => ratio_from_resolution(value)
              None => None
            }
        }
    }
    match ratio {
      Some(value) => parameters["ratio"] = Json::string(value)
      None => ()
    }
  } else if options.aspect_ratio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="Alibaba video uses model-specific resolution parameters; aspectRatio was ignored.",
      ),
    )
  }
  match provider_options.prompt_extend {
    Some(value) => parameters["prompt_extend"] = Json::boolean(value)
    None => ()
  }
  match provider_options.shot_type {
    Some(_value) if wan27 =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="shotType",
          details="wan2.7 describes shot structure in the prompt; shotType was ignored.",
        ),
      )
    Some(value) => parameters["shot_type"] = Json::string(value)
    None => ()
  }
  match provider_options.watermark {
    Some(value) => parameters["watermark"] = Json::boolean(value)
    None => ()
  }
  let audio = match options.generate_audio {
    Some(value) => Some(value)
    None => provider_options.audio
  }
  match audio {
    Some(_value) if wan27 =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="generateAudio",
          details="wan2.7 always generates audio; generateAudio was ignored.",
        ),
      )
    Some(value) => parameters["audio"] = Json::boolean(value)
    None => ()
  }
  if options.fps is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="fps",
        details="Alibaba video models do not support a custom frame rate.",
      ),
    )
  }
  {
    "model": self.model_id,
    "input": Json::object(input),
    "parameters": Json::object(parameters),
  }
}

///|
async fn AlibabaVideoModel::generate_video(
  self : AlibabaVideoModel,
  options : @provider.VideoCallOptions,
) -> @provider.VideoResponse {
  let (provider_options, option_warnings) = parse_alibaba_video_options(
    options.provider_options,
  )
  let cancellation_token = options.cancellation_token
  let warnings = option_warnings
  let body = self.create_body(options, provider_options, warnings)
  let create_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(
      self.base_url,
      "/api/v1/services/aigc/video-generation/video-synthesis",
    ),
    headers=self.request_headers(options, true),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=alibaba_video_error_message,
    transport=self.http_transport,
  )
  let task_id = match create_response.value {
    { "output": { "task_id": String(id), .. }, .. } if id != "" => id
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Alibaba video response did not contain output.task_id",
        data=create_response.value,
      )
  }
  let mut elapsed = 0
  let mut status_response : @provider_utils.JsonHttpResponse? = None
  let poll_interval_ms = provider_options.poll_interval_ms.unwrap_or(5000)
  let poll_timeout_ms = provider_options.poll_timeout_ms.unwrap_or(600_000)
  while true {
    @provider_utils.sleep_with_cancellation(
      poll_interval_ms,
      options.cancellation_token,
    )
    elapsed = elapsed + poll_interval_ms
    if elapsed > poll_timeout_ms {
      raise @provider.ProviderTimeoutError(
        provider=self.provider_name,
        operation="video_generation",
        timeout_ms=poll_timeout_ms,
      )
    }
    let response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url=@provider_utils.append_path(self.base_url, "/api/v1/tasks/" + task_id),
      headers=self.request_headers(options, false),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=alibaba_video_error_message,
      transport=self.http_transport,
    )
    let status = match response.value {
      { "output": { "task_status": String(value), .. }, .. } => value
      _ =>
        raise @provider.InvalidResponseDataError(
          message="Alibaba video status response did not contain output.task_status",
          data=response.value,
        )
    }
    if status == "SUCCEEDED" {
      status_response = Some(response)
      break
    }
    if status == "FAILED" || status == "CANCELED" {
      let message = match response.value {
        { "output": { "message": String(value), .. }, .. } => value
        _ => "Alibaba video generation failed"
      }
      raise @provider.InvalidResponseDataError(
        message="Alibaba video generation \{status.to_lower()}. Task ID: \{task_id}. \{message}",
        data=response.value,
      )
    }
  }
  let final_response = status_response.unwrap()
  let video_url = match final_response.value {
    { "output": { "video_url": String(url), .. }, .. } => url
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Alibaba video generation completed without a video URL",
        data=final_response.value,
      )
  }
  let metadata : Map[String, Json] = Map([])
  metadata["alibaba"] = alibaba_video_task_metadata(
    task_id,
    video_url,
    create_response.value,
    final_response.value,
    self.model_id,
  )
  let response_metadata = @provider.merge_response_metadata(
    Some(@provider.ResponseMetadata::new(model_id=self.model_id)),
    final_response.response,
  )
  @provider.VideoResponse::new([
    @provider.GeneratedVideo::new(
      @provider.GeneratedVideoData::Url(video_url),
      "video/mp4",
    ),
  ]).with_diagnostics(
    Some(create_response.request),
    Some(response_metadata),
    metadata,
    warnings,
  )
}

///|
pub impl @provider.VideoWireModel for AlibabaVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoWireModel for AlibabaVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoWireModel for AlibabaVideoModel with fn max_videos_per_call(
  _self,
) -> Int {
  1
}

///|
pub impl @provider.VideoWireModel for AlibabaVideoModel with fn generate(
  self,
  options,
) {
  self.generate_video(options)
}

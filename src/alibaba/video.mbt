///|
/// Alibaba DashScope asynchronous video-generation model.
priv struct AlibabaVideoModel {
  provider_name : String
  base_url : String
  api_key : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct the concrete video model behind the public V4 boundary.
fn alibaba_video_value(
  model_id : AlibabaVideoModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> AlibabaVideoModel {
  {
    provider_name: "alibaba.video",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    model_id,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn AlibabaVideoModel::request_headers_with(
  self : AlibabaVideoModel,
  request_headers : Map[String, String],
  async_request : Bool,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_alibaba_api_key(self.api_key)}"
  let merged = @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/alibaba/\{VERSION}"],
    ),
    request_headers,
  )
  // DashScope requires this marker on task creation. Keep it provider-owned
  // even when a caller supplies a differently-cased override.
  if async_request {
    @provider_utils.merge_headers(merged, { "X-DashScope-Async": "enable" })
  } else {
    merged
  }
}

///|
fn alibaba_video_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
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
  final_json : Json,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("taskId", Json::string(task_id)),
    ("videoUrl", Json::string(video_url)),
  ])
  match final_json {
    { "output": { "actual_prompt": String(value), .. }, .. } if value != "" =>
      fields["actualPrompt"] = Json::string(value)
    _ => ()
  }
  alibaba_video_usage_metadata(final_json, fields)
  Json::object(fields)
}

///|
fn alibaba_video_usage_metadata(
  final_json : Json,
  fields : Map[String, Json],
) -> Unit {
  match final_json {
    { "usage": Object(usage), .. } => {
      let usage_fields : Map[String, Json] = Map([])
      match usage.get("duration") {
        Some(Number(value, ..)) =>
          usage_fields["duration"] = Json::number(value)
        _ => ()
      }
      match usage.get("output_video_duration") {
        Some(Number(value, ..)) =>
          usage_fields["outputVideoDuration"] = Json::number(value)
        _ => ()
      }
      match usage.get("SR") {
        Some(Number(value, ..)) =>
          usage_fields["resolution"] = Json::number(value)
        _ => ()
      }
      match usage.get("size") {
        Some(String(value)) => usage_fields["size"] = Json::string(value)
        _ => ()
      }
      fields["usage"] = Json::object(usage_fields)
    }
    _ => ()
  }
}

///|
fn alibaba_video_file_value(input : @provider.VideoModelV4File) -> String {
  match input {
    @provider.VideoV4Url(url~, ..) => url
    @provider.VideoV4Data(data~, ..) => data
    @provider.VideoV4Bytes(data~, ..) =>
      @provider_utils.convert_bytes_to_base64(data)
  }
}

///|
fn find_alibaba_frame(
  frames : Array[@provider.VideoModelV4FrameImage],
  frame_type : @provider.VideoModelV4FrameType,
) -> @provider.VideoModelV4File? {
  for frame in frames {
    if frame.frame_type == frame_type {
      return Some(frame.image)
    }
  }
  None
}

///|
fn alibaba_is_video_url(url : String) -> Bool {
  let without_query = url.split("?").collect()[0]
  let path = without_query.split("#").collect()[0].to_lower()
  path.has_suffix(".mp4") || path.has_suffix(".mov")
}

///|
fn alibaba_reference_media_type(url : String) -> String {
  if alibaba_is_video_url(url) {
    "reference_video"
  } else {
    "reference_image"
  }
}

///|
fn alibaba_video_file_url(input : @provider.VideoModelV4File) -> String? {
  match input {
    @provider.VideoV4Url(url~, ..) => Some(url)
    _ => None
  }
}

///|
fn alibaba_video_frames(
  options : @provider.VideoModelV4CallOptions,
) -> Array[@provider.VideoModelV4FrameImage] {
  match options.frame_images {
    Some(values) => values
    None => []
  }
}

///|
fn alibaba_video_references(
  options : @provider.VideoModelV4CallOptions,
) -> Array[@provider.VideoModelV4File] {
  match options.input_references {
    Some(values) => values
    None => []
  }
}

///|
fn alibaba_video_start_image(
  options : @provider.VideoModelV4CallOptions,
) -> @provider.VideoModelV4File? {
  match
    find_alibaba_frame(
      alibaba_video_frames(options),
      @provider.VideoV4FirstFrame,
    ) {
    Some(value) => Some(value)
    None => options.image
  }
}

///|
fn alibaba_video_last_frame(
  options : @provider.VideoModelV4CallOptions,
) -> @provider.VideoModelV4File? {
  find_alibaba_frame(alibaba_video_frames(options), @provider.VideoV4LastFrame)
}

///|
fn alibaba_video_provider_metadata(
  task_id : String,
  video_url : String,
  final_json : Json,
) -> Map[String, Json] {
  Map([("alibaba", alibaba_video_task_metadata(task_id, video_url, final_json))])
}

///|
fn alibaba_video_result(
  task_id : String,
  video_url : String,
  final_json : Json,
  warnings : Array[@provider.Warning],
  request : @provider.RequestMetadata,
  response : @provider.ResponseMetadata,
) -> @provider.VideoModelV4Result {
  @provider.VideoModelV4Result::new(
    [@provider.VideoV4Url(url=video_url, media_type="video/mp4")],
    warnings~,
    provider_metadata=alibaba_video_provider_metadata(
      task_id, video_url, final_json,
    ),
    request~,
    response~,
  )
}

///|
fn alibaba_video_response_metadata(
  model_id : String,
  created_at : Int,
  response : @provider.ResponseMetadata,
) -> @provider.ResponseMetadata {
  @provider.merge_response_metadata(
    Some(@provider.ResponseMetadata::new(model_id~, created_at~)),
    response,
  )
}

///|
fn alibaba_video_timeout(
  provider_name : String,
  timeout_ms : Int,
) -> @provider.ProviderTimeoutError {
  @provider.ProviderTimeoutError(
    provider=provider_name,
    operation="video_generation",
    timeout_ms~,
  )
}

///|
fn alibaba_video_failure_message(
  status : String,
  task_id : String,
  response : Json,
) -> String {
  let message = match response {
    { "output": { "message": String(value), .. }, .. } => value
    _ => ""
  }
  "Alibaba video generation \{status.to_lower()}. Task ID: \{task_id}. \{message}"
}

///|
fn alibaba_video_task_id(json : Json) -> String raise {
  match json {
    { "output": { "task_id": String(id), .. }, .. } if id != "" => id
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Alibaba video response did not contain output.task_id",
        data=json,
      )
  }
}

///|
fn alibaba_video_task_status(json : Json) -> String raise {
  match json {
    { "output": { "task_status": String(value), .. }, .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Alibaba video status response did not contain output.task_status",
        data=json,
      )
  }
}

///|
fn alibaba_video_url(json : Json) -> String raise {
  match json {
    { "output": { "video_url": String(url), .. }, .. } if url != "" => url
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Alibaba video generation completed without a video URL",
        data=json,
      )
  }
}

///|
fn alibaba_video_should_warn_fps(fps : Int?) -> Bool {
  match fps {
    Some(value) => value != 0
    None => false
  }
}

///|
fn alibaba_video_should_warn_aspect_ratio(value : String?) -> Bool {
  match value {
    Some(ratio) => ratio != ""
    None => false
  }
}

///|
fn alibaba_video_has_frames(
  options : @provider.VideoModelV4CallOptions,
) -> Bool {
  alibaba_video_frames(options).length() > 0
}

///|
fn alibaba_video_reference_urls(
  options : @provider.VideoModelV4CallOptions,
  provider_options : AlibabaVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> Array[Json] {
  let urls : Array[Json] = []
  guard !alibaba_video_has_frames(options) else { return urls }
  let references = alibaba_video_references(options)
  if references.length() > 0 {
    for reference in references {
      match alibaba_video_file_url(reference) {
        Some(url) => urls.push(Json::string(url))
        None =>
          warnings.push(
            @provider.Warning::Unsupported(
              feature="inputReferences",
              details="Alibaba reference-to-video requires URL references. The inline reference was ignored.",
            ),
          )
      }
    }
  } else {
    for url in provider_options.reference_urls {
      urls.push(Json::string(url))
    }
  }
  urls
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
fn AlibabaVideoModel::create_v4_body(
  self : AlibabaVideoModel,
  options : @provider.VideoModelV4CallOptions,
  provider_options : AlibabaVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> Json {
  let mode = alibaba_video_mode(self.model_id)
  let wan27 = is_wan27(self.model_id)
  let supports_ratio = wan27 && mode != "i2v"
  let input : Map[String, Json] = Map([])
  if options.prompt is Some(value) {
    input["prompt"] = Json::string(value)
  }
  match provider_options.negative_prompt {
    Some(value) => input["negative_prompt"] = Json::string(value)
    None => ()
  }
  match provider_options.audio_url {
    Some(value) => input["audio_url"] = Json::string(value)
    None => ()
  }
  let frames = alibaba_video_frames(options)
  let references = alibaba_video_references(options)
  let first_frame_image = find_alibaba_frame(
    frames,
    @provider.VideoV4FirstFrame,
  )
  let first_frame = alibaba_video_start_image(options)
  let last_frame = alibaba_video_last_frame(options)
  if mode == "i2v" {
    match first_frame {
      Some(value) =>
        input["img_url"] = Json::string(alibaba_video_file_value(value))
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
        for reference in references {
          match reference {
            @provider.VideoV4Url(url~, ..) => {
              let kind = alibaba_reference_media_type(url)
              media.push({ "type": kind, "url": url })
            }
            @provider.VideoV4Data(media_type~, ..)
            | @provider.VideoV4Bytes(media_type~, ..) =>
              if media_type.has_prefix("image/") {
                media.push({
                  "type": "reference_image",
                  "url": @provider_utils.convert_video_model_file_to_data_uri(
                    reference,
                  ),
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
              "url": @provider_utils.convert_video_model_file_to_data_uri(value),
            })
          None => ()
        }
      }
      if media.length() > 0 {
        input["media"] = Json::array(media)
      }
    } else {
      let urls = alibaba_video_reference_urls(
        options, provider_options, warnings,
      )
      if urls.length() > 0 {
        input["reference_urls"] = Json::array(urls)
      }
    }
  }
  if last_frame is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="frameImages",
        details="Alibaba video models do not support last_frame; the last frame image was ignored.",
      ),
    )
  }
  if references.length() > 0 && mode != "r2v" {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="inputReferences",
        details="Alibaba only supports inputReferences on reference-to-video models; the references were ignored.",
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
    Some(value) if mode == "i2v" || wan27 => {
      let tier = resolution_tier(value)
      if !wan27 || tier == "720P" || tier == "1080P" {
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
  if supports_ratio {
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
  if alibaba_video_should_warn_aspect_ratio(options.aspect_ratio) &&
    !supports_ratio {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="Alibaba video uses model-specific resolution parameters; aspectRatio was ignored.",
      ),
    )
  }
  if alibaba_video_should_warn_fps(options.fps) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="fps",
        details="Alibaba video models do not support a custom frame rate.",
      ),
    )
  }
  if options.n > 1 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="n",
        details="Alibaba video models only support generating 1 video per call.",
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
async fn AlibabaVideoModel::generate_video_v4(
  self : AlibabaVideoModel,
  options : @provider.VideoModelV4CallOptions,
) -> @provider.VideoModelV4Result {
  let request_created_at = (@env.now() / 1000UL).to_int()
  let (provider_options, option_warnings) = parse_alibaba_video_options(
    options.provider_options,
  )
  let cancellation_token = options.cancellation_token
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
    cancellation_token?,
    error_to_message=alibaba_video_error_message,
    transport=self.http_transport,
  )
  let task_id = alibaba_video_task_id(create_response.value)
  let mut status_response : @provider_utils.JsonHttpResponse? = None
  let poll_interval_ms = provider_options.poll_interval_ms.unwrap_or(5000)
  let poll_timeout_ms = provider_options.poll_timeout_ms.unwrap_or(600_000)
  let poll_started_at = @env.now()
  while true {
    @provider_utils.sleep_with_cancellation(
      poll_interval_ms,
      options.cancellation_token,
    )
    if @env.now() - poll_started_at > poll_timeout_ms.to_uint64() {
      raise alibaba_video_timeout(self.provider_name, poll_timeout_ms)
    }
    let response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url=@provider_utils.append_path(self.base_url, "/api/v1/tasks/" + task_id),
      headers=self.request_headers_with(options.headers, false),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=alibaba_video_error_message,
      transport=self.http_transport,
    )
    let status = alibaba_video_task_status(response.value)
    if status == "SUCCEEDED" {
      status_response = Some(response)
      break
    }
    if status == "FAILED" || status == "CANCELED" {
      raise @provider.InvalidResponseDataError(
        message=alibaba_video_failure_message(status, task_id, response.value),
        data=response.value,
      )
    }
  }
  let final_response = status_response.unwrap()
  let video_url = alibaba_video_url(final_response.value)
  alibaba_video_result(
    task_id,
    video_url,
    final_response.value,
    warnings,
    create_response.request,
    alibaba_video_response_metadata(
      self.model_id,
      request_created_at,
      final_response.response,
    ),
  )
}

///|

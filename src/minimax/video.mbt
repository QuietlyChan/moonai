///|
/// MiniMax H3 asynchronous video-generation model.
pub struct MiniMaxVideoModel {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv model_id : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct a MiniMax video model.
pub fn minimax_video(
  model_id : MiniMaxVideoModelId,
  api_key? : String = "",
  base_url? : String = "https://api.minimax.io",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> MiniMaxVideoModel {
  {
    provider_name: "minimax.video",
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
fn MiniMaxVideoModel::request_headers(
  self : MiniMaxVideoModel,
  options : @provider.VideoCallOptions,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer " + load_minimax_api_key(self.api_key)
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/minimax/\{VERSION}"],
    ),
    options.headers,
  )
}

///|
fn minimax_video_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn minimax_input_url(input : @provider.VideoInput) -> String {
  match input {
    @provider.Url(url~, ..) => url
    @provider.Base64(data~, media_type~) =>
      "data:" + media_type + ";base64," + data
  }
}

///|
fn minimax_top_level_media_type(input : @provider.VideoInput) -> String? {
  let media_type = match input {
    @provider.Url(url=_, media_type~) => media_type
    @provider.Base64(data=_, media_type~) => Some(media_type)
  }
  match media_type {
    Some(value) if value.has_prefix("image/") => Some("image")
    Some(value) if value.has_prefix("video/") => Some("video")
    Some(value) if value.has_prefix("audio/") => Some("audio")
    Some(_) => Some("other")
    None => None
  }
}

///|
/// Frame inputs must be images. A missing media type remains acceptable for
/// URL-backed inputs because the provider-neutral video contract allows the
/// caller to omit it.
fn minimax_non_image_frame_media_type(input : @provider.VideoInput) -> String? {
  match minimax_top_level_media_type(input) {
    None | Some("image") => None
    Some(value) => Some(value)
  }
}

///|
fn minimax_resolution(value : String) -> String? {
  match value.to_upper() {
    "2K" => Some("2K")
    _ =>
      match value {
        "2048x2048"
        | "2560x1080"
        | "2560x1440"
        | "2048x1536"
        | "1440x2560"
        | "1536x2048" => Some("2K")
        _ => None
      }
  }
}

///|
fn minimax_ratio_supported(value : String) -> Bool {
  match value {
    "adaptive" | "21:9" | "16:9" | "4:3" | "1:1" | "3:4" | "9:16" => true
    _ => false
  }
}

///|
fn find_frame(
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
fn add_minimax_content(
  content : Array[Json],
  input : @provider.VideoInput,
  role : String,
  kind : String,
) -> Unit {
  let url = minimax_input_url(input)
  if kind == "video" {
    content.push({
      "type": "video_url",
      "video_url": { "url": url },
      "role": role,
    })
  } else {
    content.push({
      "type": "image_url",
      "image_url": { "url": url },
      "role": role,
    })
  }
}

///|
fn MiniMaxVideoModel::create_body(
  self : MiniMaxVideoModel,
  options : @provider.VideoCallOptions,
  provider_options : MiniMaxVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> (Json, Int, Array[String]) {
  if options.n > 1 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="n",
        details="MiniMax-H3 generates a single video per call. Only 1 video will be generated.",
      ),
    )
  }
  if options.fps is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="fps",
        details="MiniMax-H3 does not support a custom frame rate.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="MiniMax-H3 does not support a seed.",
      ),
    )
  }
  if options.generate_audio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="generateAudio",
        details="MiniMax-H3 does not expose an audio generation parameter.",
      ),
    )
  }
  let mut resolution = provider_options.resolution
  match options.resolution {
    Some(value) =>
      match (resolution, minimax_resolution(value)) {
        (Some(provider_resolution), None) =>
          warnings.push(
            @provider.Warning::Unsupported(
              feature="resolution",
              details="Unrecognized resolution \"\{value}\". MiniMax-H3 only supports \"2K\", so providerOptions.minimax.resolution (\"\{provider_resolution}\") was used instead.",
            ),
          )
        (Some(_), Some(_)) => ()
        (None, Some(mapped)) => resolution = Some(mapped)
        (None, None) =>
          warnings.push(
            @provider.Warning::Unsupported(
              feature="resolution",
              details="Unrecognized resolution \"\{value}\". MiniMax-H3 only supports \"2K\".",
            ),
          )
      }
    None => ()
  }
  let resolution = resolution.unwrap_or("2K")
  let content : Array[Json] = [{ "type": "text", "text": options.prompt }]
  let first_frame_image = find_frame(options.frame_images, @provider.FirstFrame)
  let mut first_frame = match first_frame_image {
    Some(value) => Some(value)
    None => options.image
  }
  let mut last_frame = find_frame(options.frame_images, @provider.LastFrame)
  let mut image_count = 0
  let reference_video_urls : Array[String] = []
  let mut uses_frames = false

  // Validate frame media before choosing frame mode. This prevents audio,
  // document, and other non-image inputs from being sent as image URLs.
  match first_frame {
    Some(value) =>
      match minimax_non_image_frame_media_type(value) {
        Some(media_type) => {
          let feature = if first_frame_image is Some(_) {
            "frameImages"
          } else {
            "image"
          }
          let details = if media_type == "video" {
            "MiniMax-H3 does not accept a video as a frame image. The video was ignored."
          } else {
            "MiniMax-H3 only accepts an image as a frame image; the \"\{media_type}\" file was ignored."
          }
          warnings.push(@provider.Warning::Unsupported(feature~, details~))
          first_frame = None
        }
        None => ()
      }
    None => ()
  }
  match first_frame {
    Some(value) => {
      add_minimax_content(content, value, "first_frame", "image")
      image_count = image_count + 1
      uses_frames = true
    }
    None => ()
  }
  match last_frame {
    Some(_) if !uses_frames =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="frameImages",
          details="MiniMax-H3 requires first_frame when last_frame is provided.",
        ),
      )
    Some(value) =>
      match minimax_non_image_frame_media_type(value) {
        Some(media_type) => {
          let details = if media_type == "video" {
            "MiniMax-H3 does not accept a video as a frame image. The last_frame video was ignored."
          } else {
            "MiniMax-H3 only accepts an image as a frame image; the \"\{media_type}\" last_frame was ignored."
          }
          warnings.push(
            @provider.Warning::Unsupported(feature="frameImages", details~),
          )
          last_frame = None
        }
        None => {
          add_minimax_content(content, value, "last_frame", "image")
          image_count = image_count + 1
          uses_frames = true
        }
      }
    None => ()
  }
  if uses_frames &&
    (
      options.input_references.length() > 0 ||
      provider_options.reference_audio_urls.length() > 0
    ) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="inputReferences",
        details="MiniMax-H3 cannot combine frame images with reference inputs; references were ignored.",
      ),
    )
  } else if !uses_frames {
    let mut sent_images = 0
    let mut sent_videos = 0
    for input in options.input_references {
      match minimax_top_level_media_type(input) {
        Some("video") if sent_videos < 3 => {
          add_minimax_content(content, input, "reference_video", "video")
          sent_videos = sent_videos + 1
          match input {
            @provider.Url(url~, ..) => reference_video_urls.push(url)
            _ => ()
          }
        }
        Some("video") =>
          warnings.push(
            @provider.Warning::Unsupported(
              feature="inputReferences",
              details="MiniMax-H3 accepts at most 3 reference videos; an extra video was ignored.",
            ),
          )
        Some("image") | None if sent_images < 9 => {
          if minimax_top_level_media_type(input) is None {
            warnings.push(
              @provider.Warning::Compatibility(
                feature="inputReferences",
                details="A reference without media type was treated as an image.",
              ),
            )
          }
          add_minimax_content(content, input, "reference_image", "image")
          sent_images = sent_images + 1
          image_count = image_count + 1
        }
        Some("image") | None =>
          warnings.push(
            @provider.Warning::Unsupported(
              feature="inputReferences",
              details="MiniMax-H3 accepts at most 9 reference images; an extra image was ignored.",
            ),
          )
        _ =>
          warnings.push(
            @provider.Warning::Unsupported(
              feature="inputReferences",
              details="MiniMax-H3 accepts image or video references only.",
            ),
          )
      }
    }
    if provider_options.reference_audio_urls.length() > 0 &&
      sent_images + sent_videos == 0 {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="referenceAudioUrls",
          details="MiniMax-H3 reference audio requires at least one image or video reference.",
        ),
      )
    } else {
      for index, url in provider_options.reference_audio_urls {
        if index < 3 {
          content.push({
            "type": "audio_url",
            "audio_url": { "url": url },
            "role": "reference_audio",
          })
        } else {
          warnings.push(
            @provider.Warning::Unsupported(
              feature="referenceAudioUrls",
              details="MiniMax-H3 accepts at most 3 reference audio URLs.",
            ),
          )
        }
      }
    }
  }
  let mut ratio = match provider_options.ratio {
    Some(value) => Some(value)
    None => options.aspect_ratio
  }
  if ratio is Some(value) && !minimax_ratio_supported(value) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="MiniMax-H3 does not support the requested aspect ratio.",
      ),
    )
    ratio = None
  }
  if uses_frames && ratio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="MiniMax-H3 derives aspect ratio from frame images; the requested ratio was ignored.",
      ),
    )
    ratio = None
  }
  let requested_duration = options.duration
  let mut duration = requested_duration.unwrap_or(5.0)
  if requested_duration is Some(requested) {
    if duration != duration.round() {
      duration = duration.round()
      warnings.push(
        @provider.Warning::Unsupported(
          feature="duration",
          details="MiniMax-H3 requires a whole number of seconds. The requested duration of \{requested} was rounded to \{duration}.",
        ),
      )
    }
    if duration > 15.0 {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="duration",
          details="MiniMax-H3 supports at most 15 seconds. The requested duration of \{requested} was clamped to 15.",
        ),
      )
      duration = 15.0
    } else if duration < 5.0 {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="duration",
          details="MiniMax-H3 requires at least 5 seconds. The requested duration of \{requested} was clamped to 5.",
        ),
      )
      duration = 5.0
    }
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("content", Json::array(content)),
    ("resolution", Json::string(resolution)),
    ("duration", Json::number(duration)),
  ])
  match ratio {
    Some(value) => fields["ratio"] = Json::string(value)
    None => ()
  }
  match provider_options.aigc_watermark {
    Some(value) => fields["aigc_watermark"] = Json::boolean(value)
    None => ()
  }
  (Json::object(fields), image_count, reference_video_urls)
}

///|
async fn MiniMaxVideoModel::generate_video(
  self : MiniMaxVideoModel,
  options : @provider.VideoCallOptions,
) -> @provider.VideoResponse {
  let (provider_options, option_warnings) = parse_minimax_video_options(
    options.provider_options,
  )
  let warnings = option_warnings
  let (body, image_count, reference_video_urls) = self.create_body(
    options, provider_options, warnings,
  )
  let cancellation_token = options.cancellation_token
  let create_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/v2/video_generation"),
    headers=self.request_headers(options),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=minimax_video_error_message,
    transport=self.http_transport,
  )
  let task_id = match create_response.value {
    { "task_id": String(value), .. } if value != "" => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="MiniMax video response did not contain task_id",
        data=create_response.value,
      )
  }
  let mut elapsed = 0
  let poll_interval_ms = provider_options.poll_interval_ms.unwrap_or(10_000)
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
      url=@provider_utils.append_path(
        self.base_url,
        "/v2/query/video_generation/" + task_id,
      ),
      headers=self.request_headers(options),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=minimax_video_error_message,
      transport=self.http_transport,
    )
    let status = match response.value {
      { "task": { "status": String(value), .. }, .. } => value
      _ =>
        raise @provider.InvalidResponseDataError(
          message="MiniMax video status response did not contain task.status",
          data=response.value,
        )
    }
    if status == "succeeded" {
      let video_url = match response.value {
        { "task": { "content": { "url": String(url), .. }, .. }, .. } => url
        _ =>
          raise @provider.InvalidResponseDataError(
            message="MiniMax video generation completed without a video URL",
            data=response.value,
          )
      }
      let resolved_videos : Array[Json] = [
        for value in reference_video_urls => Json::string(value)
      ]
      let provider_details : Map[String, Json] = Map([
        ("taskId", Json::string(task_id)),
        ("videoUrl", Json::string(video_url)),
        (
          "resolvedInputs",
          (
            {
              "imageCount": image_count,
              "referenceVideoUrls": Json::array(resolved_videos),
            } : Json),
        ),
      ])
      match response.value {
        { "task": { "duration": value, .. }, .. } =>
          provider_details["duration"] = value
        _ => ()
      }
      match response.value {
        { "task": { "ratio": value, .. }, .. } =>
          provider_details["ratio"] = value
        _ => ()
      }
      match response.value {
        { "task": { "resolution": value, .. }, .. } =>
          provider_details["resolution"] = value
        _ => ()
      }
      match response.value {
        { "task": { "usage": usage, .. }, .. } => {
          let usage_fields : Map[String, Json] = Map([])
          match usage {
            { "total_seconds": value, .. } =>
              usage_fields["totalSeconds"] = value
            _ => ()
          }
          match usage {
            { "input_seconds": value, .. } =>
              usage_fields["inputSeconds"] = value
            _ => ()
          }
          match usage {
            { "output_seconds": value, .. } =>
              usage_fields["outputSeconds"] = value
            _ => ()
          }
          if usage_fields.length() > 0 {
            provider_details["usage"] = Json::object(usage_fields)
          }
        }
        _ => ()
      }
      let metadata : Map[String, Json] = Map([
        ("minimax", Json::object(provider_details)),
      ])
      let response_metadata = @provider.merge_response_metadata(
        Some(@provider.ResponseMetadata::new(model_id=self.model_id)),
        response.response,
      )
      return @provider.VideoResponse::new([
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
    if status == "failed" || status == "cancelled" || status == "expired" {
      let error_message = match response.value {
        { "task": { "error": { "message": String(value), .. }, .. }, .. } =>
          Some(value)
        _ => None
      }
      let error_code = match response.value {
        { "task": { "error": { "code": String(value), .. }, .. }, .. } =>
          Some(value)
        { "task": { "error": { "code": Number(value, ..), .. }, .. }, .. } =>
          Some(value.to_int().to_string())
        _ => None
      }
      let message = match status {
        "failed" => {
          let detail = match error_message {
            Some(value) if value != "" => ": " + value
            _ => ""
          }
          let code = match error_code {
            Some(value) if value != "" => " (" + value + ")"
            _ => ""
          }
          "MiniMax video generation failed" +
          detail +
          code +
          ". Task ID: " +
          task_id
        }
        "cancelled" =>
          "MiniMax video generation was cancelled. Task ID: " + task_id
        _ => "MiniMax video generation request expired. Task ID: " + task_id
      }
      raise @provider.InvalidResponseDataError(message~, data=response.value)
    }
  }
  raise @provider.InvalidResponseDataError(
    message="MiniMax video polling ended unexpectedly",
    data=Json::string(task_id),
  )
}

///|
pub impl @provider.VideoWireModel for MiniMaxVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoWireModel for MiniMaxVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoWireModel for MiniMaxVideoModel with fn max_videos_per_call(
  _self,
) -> Int {
  1
}

///|
pub impl @provider.VideoWireModel for MiniMaxVideoModel with fn generate(
  self,
  options,
) {
  self.generate_video(options)
}

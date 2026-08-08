///|
/// MiniMax H3 asynchronous video-generation model.
priv struct MiniMaxVideoModel {
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
fn minimax_video_value(
  model_id : MiniMaxVideoModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> MiniMaxVideoModel {
  {
    provider_name: "minimax.video",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    model_id,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn MiniMaxVideoModel::request_headers_with(
  self : MiniMaxVideoModel,
  request_headers : Map[String, String],
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
    request_headers,
  )
}

///|
fn minimax_video_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => Some("MiniMax video generation error")
  }
}

///|
fn minimax_file_media_type(input : @provider.VideoModelV4File) -> String? {
  match input {
    @provider.VideoV4Url(media_type~, ..) => media_type
    @provider.VideoV4Data(media_type~, ..)
    | @provider.VideoV4Bytes(media_type~, ..) => Some(media_type)
  }
}

///|
fn minimax_top_level_media_type(input : @provider.VideoModelV4File) -> String? {
  match minimax_file_media_type(input) {
    Some(value) => Some(@provider_utils.get_top_level_media_type(value))
    None => None
  }
}

///|
/// Frame inputs must be images. A missing media type remains acceptable for
/// URL-backed inputs because the provider-neutral video contract allows the
/// caller to omit it.
fn minimax_non_image_frame_media_type(
  input : @provider.VideoModelV4File,
) -> String? {
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
fn add_minimax_content(
  content : Array[Json],
  input : @provider.VideoModelV4File,
  role : String,
  kind : String,
) -> Unit {
  let url = @provider_utils.convert_video_model_file_to_data_uri(input)
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
fn MiniMaxVideoModel::create_v4_body(
  self : MiniMaxVideoModel,
  options : @provider.VideoModelV4CallOptions,
  provider_options : MiniMaxVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> (Json, Int, Array[String]) {
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
  if options.n > 1 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="n",
        details="MiniMax-H3 generates a single video per call. Only 1 video will be generated.",
      ),
    )
  }
  if options.generate_audio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="generateAudio",
        details="The MiniMax-H3 API does not expose an audio parameter. The generateAudio option was ignored.",
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
  let frames = options.frame_images.unwrap_or([])
  let input_references = options.input_references.unwrap_or([])
  let content : Array[Json] = [
    { "type": "text", "text": options.prompt.unwrap_or("") },
  ]
  let first_frame_image = find_frame(frames, @provider.VideoV4FirstFrame)
  let mut first_frame = match first_frame_image {
    Some(value) => Some(value)
    None => options.image
  }
  let mut last_frame = find_frame(frames, @provider.VideoV4LastFrame)
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
            "MiniMax-H3 only accepts an image as a frame image; the \"\{minimax_file_media_type(value).unwrap_or(media_type)}\" file was ignored."
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
    Some(_) if !uses_frames => {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="frameImages",
          details="MiniMax-H3 requires a first_frame when a last_frame is provided. The last_frame was ignored.",
        ),
      )
      last_frame = None
    }
    Some(value) =>
      match minimax_non_image_frame_media_type(value) {
        Some(media_type) => {
          let details = if media_type == "video" {
            "MiniMax-H3 does not accept a video as a frame image. The last_frame video was ignored."
          } else {
            "MiniMax-H3 only accepts an image as a frame image; the \"\{minimax_file_media_type(value).unwrap_or(media_type)}\" last_frame was ignored."
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
      input_references.length() > 0 ||
      provider_options.reference_audio_urls.length() > 0
    ) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="inputReferences",
        details="MiniMax-H3 cannot combine frame images with reference inputs. The references were ignored.",
      ),
    )
  } else if !uses_frames {
    let reference_images : Array[@provider.VideoModelV4File] = []
    let reference_videos : Array[@provider.VideoModelV4File] = []
    for input in input_references {
      match minimax_top_level_media_type(input) {
        Some("video") => reference_videos.push(input)
        Some("image") => reference_images.push(input)
        None => {
          warnings.push(
            @provider.Warning::Unsupported(
              feature="inputReferences",
              details="MiniMax-H3 requires an explicit mediaType to route URL references as video or image. Pass { data: url, mediaType: \"video/mp4\" } for video references. The reference was treated as an image.",
            ),
          )
          reference_images.push(input)
        }
        Some(_) => {
          let media_type = minimax_file_media_type(input).unwrap_or("unknown")
          warnings.push(
            @provider.Warning::Unsupported(
              feature="inputReferences",
              details="MiniMax-H3 only accepts image and video references; the \"\{media_type}\" reference was ignored. Pass reference audio via providerOptions.minimax.referenceAudioUrls.",
            ),
          )
        }
      }
    }
    for index, input in reference_images {
      if index < 9 {
        add_minimax_content(content, input, "reference_image", "image")
        image_count = image_count + 1
      }
    }
    if reference_images.length() > 9 {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="inputReferences",
          details="MiniMax-H3 accepts at most 9 reference images. Extra images were ignored.",
        ),
      )
    }
    for index, input in reference_videos {
      if index < 3 {
        add_minimax_content(content, input, "reference_video", "video")
        if input is @provider.VideoV4Url(url~, ..) {
          reference_video_urls.push(url)
        }
      }
    }
    if reference_videos.length() > 3 {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="inputReferences",
          details="MiniMax-H3 accepts at most 3 reference videos. Extra videos were ignored.",
        ),
      )
    }
    if provider_options.reference_audio_urls.length() > 0 &&
      reference_images.length() + reference_videos.length() == 0 {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="referenceAudioUrls",
          details="MiniMax-H3 reference audio must be paired with at least one reference image or video. The audio was ignored.",
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
        }
      }
      if provider_options.reference_audio_urls.length() > 3 {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="referenceAudioUrls",
            details="MiniMax-H3 accepts at most 3 reference audios. Extra audios were ignored.",
          ),
        )
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
        details="MiniMax-H3 does not support the aspect ratio \"\{value}\". Using the provider default (adaptive).",
      ),
    )
    ratio = None
  }
  if uses_frames && ratio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="MiniMax-H3 derives the aspect ratio from the frame image; the requested ratio was ignored.",
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
async fn MiniMaxVideoModel::generate_video_v4(
  self : MiniMaxVideoModel,
  options : @provider.VideoModelV4CallOptions,
) -> @provider.VideoModelV4Result {
  let request_created_at = (@env.now() / 1000UL).to_int()
  let (provider_options, option_warnings) = parse_minimax_video_options(
    options.provider_options,
  )
  let warnings = option_warnings
  let (body, image_count, reference_video_urls) = self.create_v4_body(
    options, provider_options, warnings,
  )
  let cancellation_token = options.cancellation_token
  let create_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/v2/video_generation"),
    headers=self.request_headers_with(options.headers),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
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
  let poll_interval_ms = provider_options.poll_interval_ms.unwrap_or(10_000)
  let poll_timeout_ms = provider_options.poll_timeout_ms.unwrap_or(600_000)
  let poll_started_at = @env.now()
  while true {
    @provider_utils.sleep_with_cancellation(
      poll_interval_ms,
      options.cancellation_token,
    )
    if @env.now() - poll_started_at > poll_timeout_ms.to_uint64() {
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
      headers=self.request_headers_with(options.headers),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=minimax_video_error_message,
      validate_response=validate_minimax_video_status_response,
      transport=self.http_transport,
    )
    let status : String? = match response.value {
      { "task": { "status": String(value), .. }, .. } => Some(value)
      { "task": { "status": Null, .. }, .. } | { "task": { .. }, .. } => None
      _ =>
        raise @provider.InvalidResponseDataError(
          message="MiniMax video status response did not contain task",
          data=response.value,
        )
    }
    if status == Some("succeeded") {
      let video_url = match response.value {
        { "task": { "content": { "url": String(url), .. }, .. }, .. } if url !=
          "" => url
        _ =>
          raise @provider.InvalidResponseDataError(
            message="MiniMax video generation completed but no video URL was returned. Task ID: " +
              task_id,
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
        { "task": { "duration": Number(value, ..), .. }, .. } =>
          provider_details["duration"] = Json::number(value)
        _ => ()
      }
      match response.value {
        { "task": { "ratio": String(value), .. }, .. } =>
          provider_details["ratio"] = Json::string(value)
        _ => ()
      }
      match response.value {
        { "task": { "resolution": String(value), .. }, .. } =>
          provider_details["resolution"] = Json::string(value)
        _ => ()
      }
      match response.value {
        { "task": { "usage": Object(usage), .. }, .. } => {
          let usage_fields : Map[String, Json] = Map([])
          match usage.get("total_seconds") {
            Some(Number(value, ..)) =>
              usage_fields["totalSeconds"] = Json::number(value)
            _ => ()
          }
          match usage.get("input_seconds") {
            Some(Number(value, ..)) =>
              usage_fields["inputSeconds"] = Json::number(value)
            _ => ()
          }
          match usage.get("output_seconds") {
            Some(Number(value, ..)) =>
              usage_fields["outputSeconds"] = Json::number(value)
            _ => ()
          }
          provider_details["usage"] = Json::object(usage_fields)
        }
        _ => ()
      }
      let metadata : Map[String, Json] = Map([
        ("minimax", Json::object(provider_details)),
      ])
      let response_metadata = @provider.merge_response_metadata(
        Some(
          @provider.ResponseMetadata::new(
            model_id=self.model_id,
            created_at=request_created_at,
          ),
        ),
        response.response,
      )
      return @provider.VideoModelV4Result::new(
        [@provider.VideoV4Url(url=video_url, media_type="video/mp4")],
        warnings~,
        provider_metadata=metadata,
        request=create_response.request,
        response=response_metadata,
      )
    }
    if status == Some("failed") ||
      status == Some("cancelled") ||
      status == Some("expired") {
      let error_message = match response.value {
        { "task": { "error": { "message": String(value), .. }, .. }, .. } =>
          Some(value)
        _ => None
      }
      let error_code = match response.value {
        { "task": { "error": { "code": String(value), .. }, .. }, .. } =>
          Some(value)
        { "task": { "error": { "code": Number(value, ..), .. }, .. }, .. } =>
          Some(value.to_string())
        _ => None
      }
      let message = match status {
        Some("failed") => {
          let detail = match error_message {
            Some(value) if value != "" => ": " + value
            _ => ""
          }
          let code = match error_code {
            Some(value) => " (" + value + ")"
            _ => ""
          }
          "MiniMax video generation failed" +
          detail +
          code +
          ". Task ID: " +
          task_id
        }
        Some("cancelled") =>
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

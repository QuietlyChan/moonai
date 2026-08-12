///|
priv struct ByteDanceVideoModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id_value : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn ByteDanceVideoModel::new(
  model_id : ByteDanceVideoModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> ByteDanceVideoModel {
  {
    provider_name: "bytedance.video",
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id_value: model_id,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn find_bytedance_frame(
  frames : Array[@provider.VideoModelV4FrameImage],
  expected : @provider.VideoModelV4FrameType,
) -> @provider.VideoModelV4File? {
  for frame in frames {
    if frame.frame_type == expected {
      return Some(frame.image)
    }
  }
  None
}

///|
fn bytedance_video_resolution(value : String) -> String {
  match value {
    "864x496"
    | "496x864"
    | "752x560"
    | "560x752"
    | "640x640"
    | "992x432"
    | "432x992"
    | "864x480"
    | "480x864"
    | "736x544"
    | "544x736"
    | "960x416"
    | "416x960"
    | "832x480"
    | "480x832"
    | "624x624" => "480p"
    "1280x720"
    | "720x1280"
    | "1112x834"
    | "834x1112"
    | "960x960"
    | "1470x630"
    | "630x1470"
    | "1248x704"
    | "704x1248"
    | "1120x832"
    | "832x1120"
    | "1504x640"
    | "640x1504" => "720p"
    "1920x1080"
    | "1080x1920"
    | "1664x1248"
    | "1248x1664"
    | "1440x1440"
    | "2206x946"
    | "946x2206"
    | "1920x1088"
    | "1088x1920"
    | "2176x928"
    | "928x2176" => "1080p"
    other => other
  }
}

///|
fn video_file_media_type(file : @provider.VideoModelV4File) -> String? {
  match file {
    @provider.VideoV4Url(media_type~, ..) => media_type
    @provider.VideoV4Data(media_type~, ..) => Some(media_type)
    @provider.VideoV4Bytes(media_type~, ..) => Some(media_type)
  }
}

///|
fn video_reference_content(
  options : @provider.VideoModelV4CallOptions,
  provider_options : ByteDanceVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> Array[Json] {
  if options.frame_images.unwrap_or([]).length() > 0 {
    return []
  }
  let content : Array[Json] = []
  let references = options.input_references.unwrap_or([])
  if references.length() > 0 {
    for reference in references {
      let media_type = video_file_media_type(reference)
      if reference is @provider.VideoV4Url(media_type=None, ..) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="inputReferences",
            details="ByteDance requires media_type to distinguish URL videos; the reference was treated as an image.",
          ),
        )
      }
      let url = @provider_utils.convert_video_model_file_to_data_uri(reference)
      if media_type.unwrap_or("").has_prefix("video/") {
        content.push({
          "type": "video_url",
          "video_url": { "url": url },
          "role": "reference_video",
        })
      } else {
        content.push({
          "type": "image_url",
          "image_url": { "url": url },
          "role": "reference_image",
        })
      }
    }
  } else {
    for url in provider_options.reference_images {
      content.push({
        "type": "image_url",
        "image_url": { "url": url },
        "role": "reference_image",
      })
    }
    for url in provider_options.reference_videos {
      content.push({
        "type": "video_url",
        "video_url": { "url": url },
        "role": "reference_video",
      })
    }
  }
  content
}

///|
fn ByteDanceVideoModel::create_body(
  self : ByteDanceVideoModel,
  options : @provider.VideoModelV4CallOptions,
  provider_options : ByteDanceVideoModelOptions,
  warnings : Array[@provider.Warning],
) -> Json {
  let content : Array[Json] = []
  if options.prompt is Some(value) {
    content.push({ "type": "text", "text": value })
  }
  let frames = options.frame_images.unwrap_or([])
  let start_image = match
    find_bytedance_frame(frames, @provider.VideoV4FirstFrame) {
    Some(value) => Some(value)
    None => options.image
  }
  let last_image = match
    find_bytedance_frame(frames, @provider.VideoV4LastFrame) {
    Some(value) =>
      Some(@provider_utils.convert_video_model_file_to_data_uri(value))
    None => provider_options.last_frame_image
  }
  if start_image is Some(value) {
    let entry : Map[String, Json] = Map([
      ("type", Json::string("image_url")),
      (
        "image_url",
        { "url": @provider_utils.convert_video_model_file_to_data_uri(value) },
      ),
    ])
    if last_image is Some(_) {
      entry["role"] = Json::string("first_frame")
    }
    content.push(Json::object(entry))
  }
  if last_image is Some(value) {
    content.push({
      "type": "image_url",
      "image_url": { "url": value },
      "role": "last_frame",
    })
  }
  for entry in video_reference_content(options, provider_options, warnings) {
    content.push(entry)
  }
  for url in provider_options.reference_audio {
    content.push({
      "type": "audio_url",
      "audio_url": { "url": url },
      "role": "reference_audio",
    })
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id_value)),
    ("content", Json::array(content)),
  ])
  if options.aspect_ratio is Some(value) {
    fields["ratio"] = Json::string(value)
  }
  if options.duration is Some(value) {
    fields["duration"] = Json::number(value)
  }
  if options.seed is Some(value) {
    fields["seed"] = Json::number(value.to_double())
  }
  if options.resolution is Some(value) {
    fields["resolution"] = Json::string(bytedance_video_resolution(value))
  }
  let generate_audio = match options.generate_audio {
    Some(value) => Some(value)
    None => provider_options.generate_audio
  }
  if generate_audio is Some(value) {
    fields["generate_audio"] = Json::boolean(value)
  }
  if provider_options.watermark is Some(value) {
    fields["watermark"] = Json::boolean(value)
  }
  if provider_options.camera_fixed is Some(value) {
    fields["camera_fixed"] = Json::boolean(value)
  }
  if provider_options.return_last_frame is Some(value) {
    fields["return_last_frame"] = Json::boolean(value)
  }
  if provider_options.service_tier is Some(value) {
    fields["service_tier"] = Json::string(value)
  }
  if provider_options.draft is Some(value) {
    fields["draft"] = Json::boolean(value)
  }
  for entry in provider_options.extensions.iter2() {
    fields[entry.0] = entry.1
  }
  if options.fps is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="fps",
        details="ByteDance Seedance uses a fixed 24 fps frame rate.",
      ),
    )
  }
  if options.n > 1 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="n",
        details="ByteDance video models generate one video per call.",
      ),
    )
  }
  Json::object(fields)
}

///|
fn bytedance_task_id(json : Json) -> String raise {
  match json {
    { "id": String(id), .. } if id != "" => id
    _ =>
      raise @provider.InvalidResponseDataError(
        message="ByteDance video response did not contain a task id",
        data=json,
      )
  }
}

///|
fn bytedance_task_status(json : Json) -> String raise {
  match json {
    { "status": String(status), .. } => status
    _ =>
      raise @provider.InvalidResponseDataError(
        message="ByteDance video status response did not contain status",
        data=json,
      )
  }
}

///|
fn bytedance_video_url(json : Json) -> String raise {
  match json {
    { "content": { "video_url": String(url), .. }, .. } if url != "" => url
    _ =>
      raise @provider.InvalidResponseDataError(
        message="ByteDance video generation completed without a video URL",
        data=json,
      )
  }
}

///|
fn bytedance_failure_message(task_id : String, json : Json) -> String {
  let message = match json {
    { "error": { "message": String(value), .. }, .. } => value
    { "message": String(value), .. } => value
    _ => json.stringify()
  }
  "ByteDance video generation failed. Task ID: \{task_id}. \{message}"
}

///|
async fn ByteDanceVideoModel::generate(
  self : ByteDanceVideoModel,
  options : @provider.VideoModelV4CallOptions,
) -> @provider.VideoModelV4Result {
  let (provider_options, option_warnings) = parse_bytedance_video_options(
    options.provider_options,
  )
  let warnings = option_warnings
  let body = self.create_body(options, provider_options, warnings)
  let headers = bytedance_headers(self.api_key, self.headers, options.headers)
  let create_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(
      self.base_url,
      "/contents/generations/tasks",
    ),
    headers~,
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=bytedance_error_message,
    transport=self.http_transport,
  )
  let task_id = bytedance_task_id(create_response.value)
  let poll_interval_ms = provider_options.poll_interval_ms.unwrap_or(3000)
  let poll_timeout_ms = provider_options.poll_timeout_ms.unwrap_or(300_000)
  let started_at = @env.now()
  let mut final_response : @provider_utils.JsonHttpResponse? = None
  while true {
    let response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url=@provider_utils.append_path(
        self.base_url,
        "/contents/generations/tasks/" + task_id,
      ),
      headers~,
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?=options.cancellation_token,
      error_to_message=bytedance_error_message,
      transport=self.http_transport,
    )
    let status = bytedance_task_status(response.value).to_lower()
    if status == "succeeded" {
      final_response = Some(response)
      break
    }
    if status == "failed" || status == "canceled" {
      raise @provider.InvalidResponseDataError(
        message=bytedance_failure_message(task_id, response.value),
        data=response.value,
      )
    }
    if @env.now() - started_at > poll_timeout_ms.to_uint64() {
      raise @provider.ProviderTimeoutError(
        provider=self.provider_name,
        operation="video_generation",
        timeout_ms=poll_timeout_ms,
      )
    }
    @provider_utils.sleep_with_cancellation(
      poll_interval_ms,
      options.cancellation_token,
    )
  }
  let response = final_response.unwrap()
  let video_url = bytedance_video_url(response.value)
  let metadata : Map[String, Json] = Map([("taskId", Json::string(task_id))])
  match response.value {
    { "usage": value, .. } if !(value is Null) => metadata["usage"] = value
    _ => ()
  }
  @provider.VideoModelV4Result::new(
    [@provider.VideoV4Url(url=video_url, media_type="video/mp4")],
    warnings~,
    provider_metadata={ "bytedance": Json::object(metadata) },
    request=create_response.request,
    response=@provider.merge_response_metadata(
      Some(response.response),
      @provider.ResponseMetadata::new(
        model_id=self.model_id_value,
        created_at=(@env.now() / 1000UL).to_int(),
      ),
    ),
  )
}

///|
impl @provider.VideoModelV4 for ByteDanceVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.VideoModelV4 for ByteDanceVideoModel with fn provider(self) {
  self.provider_name
}

///|
impl @provider.VideoModelV4 for ByteDanceVideoModel with fn model_id(self) {
  self.model_id_value
}

///|
impl @provider.VideoModelV4 for ByteDanceVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
impl @provider.VideoModelV4 for ByteDanceVideoModel with fn do_generate(
  self,
  options,
) {
  self.generate(options)
}

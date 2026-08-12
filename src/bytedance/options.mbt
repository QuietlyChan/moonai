///|
/// ByteDance Seedream image model identifier.
pub type ByteDanceImageModelId = String

///|
/// ByteDance Seedance video model identifier.
pub type ByteDanceVideoModelId = String

///|
/// Typed Seedream image-generation options.
pub(all) struct ByteDanceImageModelOptions {
  watermark : Bool?
  output_format : String?
  size : String?
  sequential_image_generation : String?
  max_images : Int?
  optimize_prompt_mode : String?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct validated Seedream image options.
pub fn ByteDanceImageModelOptions::new(
  watermark? : Bool,
  output_format? : String,
  size? : String,
  sequential_image_generation? : String,
  max_images? : Int,
  optimize_prompt_mode? : String,
  extensions? : Map[String, Json] = Map([]),
) -> ByteDanceImageModelOptions raise {
  if output_format is Some(value) {
    guard value == "png" || value == "jpeg" else {
      fail("ByteDance image output_format must be png or jpeg")
    }
  }
  if sequential_image_generation is Some(value) {
    guard value == "auto" || value == "disabled" else {
      fail("ByteDance sequential_image_generation must be auto or disabled")
    }
  }
  if max_images is Some(value) {
    guard value > 0 else { fail("ByteDance max_images must be positive") }
  }
  if optimize_prompt_mode is Some(value) {
    guard value == "standard" || value == "fast" else {
      fail("ByteDance optimize_prompt_mode must be standard or fast")
    }
  }
  {
    watermark,
    output_format,
    size,
    sequential_image_generation,
    max_images,
    optimize_prompt_mode,
    extensions: @provider.copy_provider_metadata(extensions),
  }
}

///|
/// Convert image options to `providerOptions.bytedance`.
pub fn ByteDanceImageModelOptions::to_provider_options(
  self : ByteDanceImageModelOptions,
) -> Map[String, Json] {
  let values = @provider.copy_provider_metadata(self.extensions)
  if self.watermark is Some(value) {
    values["watermark"] = Json::boolean(value)
  }
  if self.output_format is Some(value) {
    values["outputFormat"] = Json::string(value)
  }
  if self.size is Some(value) {
    values["size"] = Json::string(value)
  }
  if self.sequential_image_generation is Some(value) {
    values["sequentialImageGeneration"] = Json::string(value)
  }
  if self.max_images is Some(value) {
    values["maxImages"] = Json::number(value.to_double())
  }
  if self.optimize_prompt_mode is Some(value) {
    values["optimizePromptMode"] = Json::string(value)
  }
  Map([("bytedance", Json::object(values))])
}

///|
/// Typed Seedance asynchronous video-generation options.
pub(all) struct ByteDanceVideoModelOptions {
  watermark : Bool?
  generate_audio : Bool?
  camera_fixed : Bool?
  return_last_frame : Bool?
  service_tier : String?
  draft : Bool?
  last_frame_image : String?
  reference_images : Array[String]
  reference_videos : Array[String]
  reference_audio : Array[String]
  poll_interval_ms : Int?
  poll_timeout_ms : Int?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct validated Seedance video options.
pub fn ByteDanceVideoModelOptions::new(
  watermark? : Bool,
  generate_audio? : Bool,
  camera_fixed? : Bool,
  return_last_frame? : Bool,
  service_tier? : String,
  draft? : Bool,
  last_frame_image? : String,
  reference_images? : Array[String] = [],
  reference_videos? : Array[String] = [],
  reference_audio? : Array[String] = [],
  poll_interval_ms? : Int,
  poll_timeout_ms? : Int,
  extensions? : Map[String, Json] = Map([]),
) -> ByteDanceVideoModelOptions raise {
  if service_tier is Some(value) {
    guard value == "default" || value == "flex" else {
      fail("ByteDance service_tier must be default or flex")
    }
  }
  if poll_interval_ms is Some(value) {
    guard value > 0 else { fail("ByteDance poll_interval_ms must be positive") }
  }
  if poll_timeout_ms is Some(value) {
    guard value > 0 else { fail("ByteDance poll_timeout_ms must be positive") }
  }
  {
    watermark,
    generate_audio,
    camera_fixed,
    return_last_frame,
    service_tier,
    draft,
    last_frame_image,
    reference_images: reference_images.copy(),
    reference_videos: reference_videos.copy(),
    reference_audio: reference_audio.copy(),
    poll_interval_ms,
    poll_timeout_ms,
    extensions: @provider.copy_provider_metadata(extensions),
  }
}

///|
fn string_array_json(values : Array[String]) -> Json {
  Json::array([ for value in values => Json::string(value) ])
}

///|
/// Convert video options to `providerOptions.bytedance`.
pub fn ByteDanceVideoModelOptions::to_provider_options(
  self : ByteDanceVideoModelOptions,
) -> Map[String, Json] {
  let values = @provider.copy_provider_metadata(self.extensions)
  if self.watermark is Some(value) {
    values["watermark"] = Json::boolean(value)
  }
  if self.generate_audio is Some(value) {
    values["generateAudio"] = Json::boolean(value)
  }
  if self.camera_fixed is Some(value) {
    values["cameraFixed"] = Json::boolean(value)
  }
  if self.return_last_frame is Some(value) {
    values["returnLastFrame"] = Json::boolean(value)
  }
  if self.service_tier is Some(value) {
    values["serviceTier"] = Json::string(value)
  }
  if self.draft is Some(value) {
    values["draft"] = Json::boolean(value)
  }
  if self.last_frame_image is Some(value) {
    values["lastFrameImage"] = Json::string(value)
  }
  if self.reference_images.length() > 0 {
    values["referenceImages"] = string_array_json(self.reference_images)
  }
  if self.reference_videos.length() > 0 {
    values["referenceVideos"] = string_array_json(self.reference_videos)
  }
  if self.reference_audio.length() > 0 {
    values["referenceAudio"] = string_array_json(self.reference_audio)
  }
  if self.poll_interval_ms is Some(value) {
    values["pollIntervalMs"] = Json::number(value.to_double())
  }
  if self.poll_timeout_ms is Some(value) {
    values["pollTimeoutMs"] = Json::number(value.to_double())
  }
  Map([("bytedance", Json::object(values))])
}

///|
fn read_string_array(
  reader : @provider_utils.ProviderOptionsReader,
  field : String,
) -> Array[String] {
  let result : Array[String] = []
  match reader.take_array(field) {
    Some(values) =>
      for value in values {
        match value {
          String(text) => result.push(text)
          _ =>
            reader.add_warning(
              @provider.Warning::Compatibility(
                feature="providerOptions.bytedance.\{field}",
                details="Expected an array of strings; the invalid item was ignored.",
              ),
            )
        }
      }
    None => ()
  }
  result
}

///|
fn parse_bytedance_image_options(
  provider_options : Map[String, Json],
) -> (ByteDanceImageModelOptions, Array[@provider.Warning]) {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="bytedance",
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let options : ByteDanceImageModelOptions = {
    watermark: reader.take_bool("watermark"),
    output_format: reader.take_string(
      "outputFormat",
      aliases=["output_format"],
      allowed=["png", "jpeg"],
    ),
    size: reader.take_string("size"),
    sequential_image_generation: reader.take_string(
      "sequentialImageGeneration",
      aliases=["sequential_image_generation"],
      allowed=["auto", "disabled"],
    ),
    max_images: reader.take_int("maxImages", aliases=["max_images"], min=1),
    optimize_prompt_mode: reader.take_string(
      "optimizePromptMode",
      aliases=["optimize_prompt_mode"],
      allowed=["standard", "fast"],
    ),
    extensions: reader.remaining_values(),
  }
  (options, reader.diagnostics())
}

///|
fn parse_bytedance_video_options(
  provider_options : Map[String, Json],
) -> (ByteDanceVideoModelOptions, Array[@provider.Warning]) {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="bytedance",
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let options : ByteDanceVideoModelOptions = {
    watermark: reader.take_bool("watermark"),
    generate_audio: reader.take_bool("generateAudio", aliases=["generate_audio"]),
    camera_fixed: reader.take_bool("cameraFixed", aliases=["camera_fixed"]),
    return_last_frame: reader.take_bool("returnLastFrame", aliases=[
      "return_last_frame",
    ]),
    service_tier: reader.take_string("serviceTier", aliases=["service_tier"], allowed=[
      "default", "flex",
    ]),
    draft: reader.take_bool("draft"),
    last_frame_image: reader.take_string("lastFrameImage", aliases=[
      "last_frame_image",
    ]),
    reference_images: read_string_array(reader, "referenceImages"),
    reference_videos: read_string_array(reader, "referenceVideos"),
    reference_audio: read_string_array(reader, "referenceAudio"),
    poll_interval_ms: reader.take_int(
      "pollIntervalMs",
      aliases=["poll_interval_ms"],
      min=1,
    ),
    poll_timeout_ms: reader.take_int(
      "pollTimeoutMs",
      aliases=["poll_timeout_ms"],
      min=1,
    ),
    extensions: reader.remaining_values(),
  }
  (options, reader.diagnostics())
}

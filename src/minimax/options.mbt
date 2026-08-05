///|
/// MiniMax chat model identifier.
pub type MiniMaxChatModelId = String

///|
/// MiniMax video model identifier.
pub type MiniMaxVideoModelId = String

///|
/// MiniMax Anthropic-compatible thinking mode.
pub(all) enum MiniMaxThinkingMode {
  AdaptiveThinking
  DisabledThinking
} derive(Debug, Eq)

///|
/// Provider-specific options for MiniMax language models.
pub(all) struct MiniMaxLanguageModelOptions {
  thinking : MiniMaxThinkingMode?
} derive(Debug, Eq)

///|
/// Construct MiniMax language-model options.
pub fn MiniMaxLanguageModelOptions::new(
  thinking? : MiniMaxThinkingMode,
) -> MiniMaxLanguageModelOptions {
  { thinking, }
}

///|
/// Convert typed MiniMax options into the shared provider-options map.
pub fn MiniMaxLanguageModelOptions::to_provider_options(
  self : MiniMaxLanguageModelOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.thinking is Some(mode) {
    values["thinking"] = {
      "type": match mode {
        AdaptiveThinking => "adaptive"
        DisabledThinking => "disabled"
      },
    }
  }
  Map([("minimax", Json::object(values))])
}

///|
/// Provider-specific MiniMax video options.
pub(all) struct MiniMaxVideoModelOptions {
  resolution : String?
  ratio : String?
  reference_audio_urls : Array[String]
  aigc_watermark : Bool?
  poll_interval_ms : Int?
  poll_timeout_ms : Int?
} derive(Debug, Eq)

///|
/// Construct and validate typed MiniMax video options.
pub fn MiniMaxVideoModelOptions::new(
  resolution? : String,
  ratio? : String,
  reference_audio_urls? : Array[String] = [],
  aigc_watermark? : Bool,
  poll_interval_ms? : Int,
  poll_timeout_ms? : Int,
) -> MiniMaxVideoModelOptions raise {
  if resolution is Some(value) {
    guard value == "2K" else { fail("MiniMax video resolution must be 2K") }
  }
  if ratio is Some(value) {
    guard value == "adaptive" ||
      value == "21:9" ||
      value == "16:9" ||
      value == "4:3" ||
      value == "1:1" ||
      value == "3:4" ||
      value == "9:16" else {
      fail("MiniMax video ratio is not supported")
    }
  }
  if poll_interval_ms is Some(value) {
    guard value > 0 else {
      fail("MiniMax video poll_interval_ms must be positive")
    }
  }
  if poll_timeout_ms is Some(value) {
    guard value > 0 else {
      fail("MiniMax video poll_timeout_ms must be positive")
    }
  }
  {
    resolution,
    ratio,
    reference_audio_urls: reference_audio_urls.copy(),
    aigc_watermark,
    poll_interval_ms,
    poll_timeout_ms,
  }
}

///|
/// Convert typed MiniMax video options into the provider namespace.
pub fn MiniMaxVideoModelOptions::to_provider_options(
  self : MiniMaxVideoModelOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.resolution is Some(value) {
    values["resolution"] = Json::string(value)
  }
  if self.ratio is Some(value) {
    values["ratio"] = Json::string(value)
  }
  if self.reference_audio_urls.length() > 0 {
    values["referenceAudioUrls"] = Json::array(
      [
        for value in self.reference_audio_urls => Json::string(value)
      ],
    )
  }
  if self.aigc_watermark is Some(value) {
    values["aigcWatermark"] = Json::boolean(value)
  }
  if self.poll_interval_ms is Some(value) {
    values["pollIntervalMs"] = Json::number(value.to_double())
  }
  if self.poll_timeout_ms is Some(value) {
    values["pollTimeoutMs"] = Json::number(value.to_double())
  }
  Map([("minimax", Json::object(values))])
}

///|
fn parse_minimax_video_options(
  provider_options : Map[String, Json],
) -> (MiniMaxVideoModelOptions, Array[@provider.Warning]) {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="minimax.video",
    aliases=["minimax"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let reference_audio_urls : Array[String] = []
  match
    reader.take_array("referenceAudioUrls", aliases=["reference_audio_urls"]) {
    Some(values) =>
      for value in values {
        match value {
          String(url) => reference_audio_urls.push(url)
          _ =>
            reader.add_warning(
              @provider.Warning::Compatibility(
                feature="providerOptions.minimax.referenceAudioUrls",
                details="Expected an array of strings; an invalid entry was ignored.",
              ),
            )
        }
      }
    None => ()
  }
  let options = {
    resolution: reader.take_string("resolution", allowed=["2K"]),
    ratio: reader.take_string("ratio", allowed=[
      "adaptive", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16",
    ]),
    reference_audio_urls,
    aigc_watermark: reader.take_bool("aigcWatermark", aliases=["aigc_watermark"]),
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
  }
  (options, reader.diagnostics())
}

///|
/// Qwen chat model identifiers. The open string tail keeps the provider
/// forward-compatible with newly released DashScope models.
pub type AlibabaChatModelId = String

///|
/// Alibaba text embedding model identifiers.
pub type AlibabaEmbeddingModelId = String

///|
/// Alibaba video model identifiers.
pub type AlibabaVideoModelId = String

///|
/// Provider-specific Alibaba chat options.
pub(all) struct AlibabaLanguageModelChatOptions {
  enable_thinking : Bool?
  thinking_budget : Int?
  parallel_tool_calls : Bool?
} derive(Debug, Eq)

///|
/// Construct Alibaba chat options.
pub fn AlibabaLanguageModelChatOptions::new(
  enable_thinking? : Bool,
  thinking_budget? : Int,
  parallel_tool_calls? : Bool,
) -> AlibabaLanguageModelChatOptions raise {
  if thinking_budget is Some(value) {
    guard value > 0 else { fail("Alibaba thinking_budget must be positive") }
  }
  { enable_thinking, thinking_budget, parallel_tool_calls }
}

///|
/// Convert Alibaba chat options into the provider-options namespace.
pub fn AlibabaLanguageModelChatOptions::to_provider_options(
  self : AlibabaLanguageModelChatOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.enable_thinking is Some(value) {
    values["enableThinking"] = Json::boolean(value)
  }
  if self.thinking_budget is Some(value) {
    values["thinkingBudget"] = Json::number(value.to_double())
  }
  if self.parallel_tool_calls is Some(value) {
    values["parallelToolCalls"] = Json::boolean(value)
  }
  Map([("alibaba", Json::object(values))])
}

///|
/// Provider-specific Alibaba embedding options.
pub(all) struct AlibabaEmbeddingModelOptions {
  text_type : String?
  dimension : Int?
  output_type : String?
} derive(Debug, Eq)

///|
/// Construct Alibaba embedding options.
pub fn AlibabaEmbeddingModelOptions::new(
  text_type? : String,
  dimension? : Int,
  output_type? : String,
) -> AlibabaEmbeddingModelOptions raise {
  if text_type is Some(value) {
    guard value == "query" || value == "document" else {
      fail("Alibaba embedding text_type must be query or document")
    }
  }
  if dimension is Some(value) {
    guard value > 0 else {
      fail("Alibaba embedding dimension must be positive")
    }
  }
  if output_type is Some(value) {
    guard value == "dense" || value == "sparse" || value == "dense&sparse" else {
      fail(
        "Alibaba embedding output_type must be dense, sparse, or dense&sparse",
      )
    }
  }
  { text_type, dimension, output_type }
}

///|
/// Convert Alibaba embedding options into the provider-options namespace.
pub fn AlibabaEmbeddingModelOptions::to_provider_options(
  self : AlibabaEmbeddingModelOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.text_type is Some(value) {
    values["textType"] = Json::string(value)
  }
  if self.dimension is Some(value) {
    values["dimension"] = Json::number(value.to_double())
  }
  if self.output_type is Some(value) {
    values["outputType"] = Json::string(value)
  }
  Map([("alibaba", Json::object(values))])
}

///|
/// Provider-specific Alibaba video options.
pub(all) struct AlibabaVideoModelOptions {
  negative_prompt : String?
  audio_url : String?
  prompt_extend : Bool?
  shot_type : String?
  watermark : Bool?
  audio : Bool?
  reference_urls : Array[String]
  ratio : String?
  media : Array[AlibabaVideoMedia]
  poll_interval_ms : Int?
  poll_timeout_ms : Int?
} derive(Debug, Eq)

///|
/// A native DashScope wan2.7 media item.
pub(all) struct AlibabaVideoMedia {
  media_type : String
  url : String
  reference_voice : String?
} derive(Debug, Eq)

///|
/// Construct and validate a DashScope wan2.7 media item.
pub fn AlibabaVideoMedia::new(
  media_type~ : String,
  url~ : String,
  reference_voice? : String,
) -> AlibabaVideoMedia raise {
  guard media_type == "reference_image" ||
    media_type == "reference_video" ||
    media_type == "first_frame" else {
    fail(
      "Alibaba video media_type must be reference_image, reference_video, or first_frame",
    )
  }
  { media_type, url, reference_voice }
}

///|
/// Construct and validate typed Alibaba video options.
pub fn AlibabaVideoModelOptions::new(
  negative_prompt? : String,
  audio_url? : String,
  prompt_extend? : Bool,
  shot_type? : String,
  watermark? : Bool,
  audio? : Bool,
  reference_urls? : Array[String] = [],
  ratio? : String,
  media? : Array[AlibabaVideoMedia] = [],
  poll_interval_ms? : Int,
  poll_timeout_ms? : Int,
) -> AlibabaVideoModelOptions raise {
  if shot_type is Some(value) {
    guard value == "single" || value == "multi" else {
      fail("Alibaba video shot_type must be single or multi")
    }
  }
  if ratio is Some(value) {
    guard value == "16:9" ||
      value == "9:16" ||
      value == "1:1" ||
      value == "4:3" ||
      value == "3:4" else {
      fail("Alibaba video ratio is not supported")
    }
  }
  if poll_interval_ms is Some(value) {
    guard value > 0 else {
      fail("Alibaba video poll_interval_ms must be positive")
    }
  }
  if poll_timeout_ms is Some(value) {
    guard value > 0 else {
      fail("Alibaba video poll_timeout_ms must be positive")
    }
  }
  {
    negative_prompt,
    audio_url,
    prompt_extend,
    shot_type,
    watermark,
    audio,
    reference_urls: reference_urls.copy(),
    ratio,
    media: media.copy(),
    poll_interval_ms,
    poll_timeout_ms,
  }
}

///|
/// Convert typed Alibaba video options into the provider namespace.
pub fn AlibabaVideoModelOptions::to_provider_options(
  self : AlibabaVideoModelOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.negative_prompt is Some(value) {
    values["negativePrompt"] = Json::string(value)
  }
  if self.audio_url is Some(value) {
    values["audioUrl"] = Json::string(value)
  }
  if self.prompt_extend is Some(value) {
    values["promptExtend"] = Json::boolean(value)
  }
  if self.shot_type is Some(value) {
    values["shotType"] = Json::string(value)
  }
  if self.watermark is Some(value) {
    values["watermark"] = Json::boolean(value)
  }
  if self.audio is Some(value) {
    values["audio"] = Json::boolean(value)
  }
  if self.reference_urls.length() > 0 {
    values["referenceUrls"] = Json::array(
      [
        for value in self.reference_urls => Json::string(value)
      ],
    )
  }
  if self.ratio is Some(value) {
    values["ratio"] = Json::string(value)
  }
  if self.media.length() > 0 {
    values["media"] = Json::array(
      [
        for item in self.media => {
          Json::object(
            Map(
              [
                ("type", Json::string(item.media_type)),
                ("url", Json::string(item.url)),
                ..if item.reference_voice is Some(value) {
                  [("referenceVoice", Json::string(value))]
                },
              ],
            ),
          )
        }
      ],
    )
  }
  if self.poll_interval_ms is Some(value) {
    values["pollIntervalMs"] = Json::number(value.to_double())
  }
  if self.poll_timeout_ms is Some(value) {
    values["pollTimeoutMs"] = Json::number(value.to_double())
  }
  Map([("alibaba", Json::object(values))])
}

///|
/// Parse Alibaba's provider namespace for native text embeddings.
fn parse_alibaba_embedding_options(
  provider_options : Map[String, Json],
) -> (AlibabaEmbeddingModelOptions, Array[@provider.Warning]) {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="alibaba.embedding",
    aliases=["alibaba"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let options = {
    text_type: reader.take_string("textType", aliases=["text_type"], allowed=[
      "query", "document",
    ]),
    dimension: reader.take_int("dimension", min=1),
    output_type: reader.take_string("outputType", aliases=["output_type"], allowed=[
      "dense", "sparse", "dense&sparse",
    ]),
  }
  (options, reader.diagnostics())
}

///|
/// Parse Alibaba's provider namespace for asynchronous video generation.
fn parse_alibaba_video_options(
  provider_options : Map[String, Json],
) -> (AlibabaVideoModelOptions, Array[@provider.Warning]) {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="alibaba.video",
    aliases=["alibaba"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let reference_urls : Array[String] = []
  match reader.take_array("referenceUrls", aliases=["reference_urls"]) {
    Some(values) =>
      for value in values {
        match value {
          String(url) => reference_urls.push(url)
          _ =>
            reader.add_warning(
              @provider.Warning::Compatibility(
                feature="providerOptions.alibaba.referenceUrls",
                details="Expected an array of strings; an invalid entry was ignored.",
              ),
            )
        }
      }
    None => ()
  }
  let media : Array[AlibabaVideoMedia] = []
  match reader.take_array("media") {
    Some(values) =>
      for value in values {
        match value {
          { "type": String(media_type), "url": String(url), .. } if media_type ==
            "reference_image" ||
            media_type == "reference_video" ||
            media_type == "first_frame" => {
            let reference_voice = match value {
              { "referenceVoice": String(voice), .. } => Some(voice)
              { "reference_voice": String(voice), .. } => Some(voice)
              _ => None
            }
            media.push({ media_type, url, reference_voice })
          }
          _ =>
            reader.add_warning(
              @provider.Warning::Compatibility(
                feature="providerOptions.alibaba.media",
                details="Expected a supported media object; an invalid entry was ignored.",
              ),
            )
        }
      }
    None => ()
  }
  let poll_interval_ms = reader.take_int(
    "pollIntervalMs",
    aliases=["poll_interval_ms"],
    min=1,
  )
  let poll_timeout_ms = reader.take_int(
    "pollTimeoutMs",
    aliases=["poll_timeout_ms"],
    min=1,
  )
  let options = {
    negative_prompt: reader.take_string("negativePrompt", aliases=[
      "negative_prompt",
    ]),
    audio_url: reader.take_string("audioUrl", aliases=["audio_url"]),
    prompt_extend: reader.take_bool("promptExtend", aliases=["prompt_extend"]),
    shot_type: reader.take_string("shotType", aliases=["shot_type"], allowed=[
      "single", "multi",
    ]),
    watermark: reader.take_bool("watermark"),
    audio: reader.take_bool("audio"),
    reference_urls,
    ratio: reader.take_string("ratio", allowed=[
      "16:9", "9:16", "1:1", "4:3", "3:4",
    ]),
    media,
    poll_interval_ms,
    poll_timeout_ms,
  }
  (options, reader.diagnostics())
}

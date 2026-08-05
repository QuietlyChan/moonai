///|
/// Identifier accepted by an OpenAI-compatible chat endpoint.
pub type OpenAICompatibleChatModelId = String

///|
/// Identifier accepted by an OpenAI-compatible completion endpoint.
pub type OpenAICompatibleCompletionModelId = String

///|
/// Identifier accepted by an OpenAI-compatible embedding endpoint.
pub type OpenAICompatibleEmbeddingModelId = String

///|
fn compatible_namespaced_options(
  provider_name : String,
  values : Map[String, Json],
) -> Map[String, Json] {
  Map([(provider_name, Json::object(values))])
}

///|
/// Typed provider options for OpenAI-compatible chat models.
pub(all) struct OpenAICompatibleLanguageModelChatOptions {
  user : String?
  reasoning_effort : String?
  text_verbosity : String?
  strict_json_schema : Bool?
} derive(Debug, Eq)

///|
/// Construct typed OpenAI-compatible chat options.
pub fn OpenAICompatibleLanguageModelChatOptions::new(
  user? : String,
  reasoning_effort? : String,
  text_verbosity? : String,
  strict_json_schema? : Bool,
) -> OpenAICompatibleLanguageModelChatOptions {
  { user, reasoning_effort, text_verbosity, strict_json_schema }
}

///|
/// Convert chat options to a provider namespace.
pub fn OpenAICompatibleLanguageModelChatOptions::to_provider_options(
  self : OpenAICompatibleLanguageModelChatOptions,
  provider_name? : String = "openaiCompatible",
) -> Map[String, Json] {
  compatible_namespaced_options(
    provider_name,
    Map(
      [
        ..if self.user is Some(value) {
          [("user", Json::string(value))]
        },
        ..if self.reasoning_effort is Some(value) {
          [("reasoningEffort", Json::string(value))]
        },
        ..if self.text_verbosity is Some(value) {
          [("textVerbosity", Json::string(value))]
        },
        ..if self.strict_json_schema is Some(value) {
          [("strictJsonSchema", Json::boolean(value))]
        },
      ],
    ),
  )
}

///|
/// Typed provider options for OpenAI-compatible legacy completions.
pub(all) struct OpenAICompatibleLanguageModelCompletionOptions {
  echo : Bool?
  logit_bias : Map[String, Double]?
  suffix : String?
  user : String?
} derive(Debug, Eq)

///|
/// Construct typed OpenAI-compatible completion options.
pub fn OpenAICompatibleLanguageModelCompletionOptions::new(
  echo? : Bool,
  logit_bias? : Map[String, Double],
  suffix? : String,
  user? : String,
) -> OpenAICompatibleLanguageModelCompletionOptions {
  { echo, logit_bias, suffix, user }
}

///|
/// Convert completion options to a provider namespace.
pub fn OpenAICompatibleLanguageModelCompletionOptions::to_provider_options(
  self : OpenAICompatibleLanguageModelCompletionOptions,
  provider_name? : String = "openaiCompatible",
) -> Map[String, Json] {
  let bias_json = match self.logit_bias {
    Some(values) => {
      let fields : Map[String, Json] = Map([])
      for entry in values.iter2() {
        fields[entry.0] = Json::number(entry.1)
      }
      Some(Json::object(fields))
    }
    None => None
  }
  compatible_namespaced_options(
    provider_name,
    Map(
      [
        ..if self.echo is Some(value) {
          [("echo", Json::boolean(value))]
        },
        ..if bias_json is Some(value) {
          [("logitBias", value)]
        },
        ..if self.suffix is Some(value) {
          [("suffix", Json::string(value))]
        },
        ..if self.user is Some(value) {
          [("user", Json::string(value))]
        },
      ],
    ),
  )
}

///|
/// Typed provider options for OpenAI-compatible embedding models.
pub(all) struct OpenAICompatibleEmbeddingModelOptions {
  dimensions : Int?
  user : String?
} derive(Debug, Eq)

///|
/// Construct typed OpenAI-compatible embedding options.
pub fn OpenAICompatibleEmbeddingModelOptions::new(
  dimensions? : Int,
  user? : String,
) -> OpenAICompatibleEmbeddingModelOptions {
  { dimensions, user }
}

///|
/// Convert embedding options to a provider namespace.
pub fn OpenAICompatibleEmbeddingModelOptions::to_provider_options(
  self : OpenAICompatibleEmbeddingModelOptions,
  provider_name? : String = "openaiCompatible",
) -> Map[String, Json] {
  compatible_namespaced_options(
    provider_name,
    Map(
      [
        ..if self.dimensions is Some(value) {
          [("dimensions", Json::number(value.to_double()))]
        },
        ..if self.user is Some(value) {
          [("user", Json::string(value))]
        },
      ],
    ),
  )
}

///|
/// Common and provider-specific options for OpenAI-compatible image models.
///
/// Unknown provider fields can be supplied through extensions, matching the
/// loose object schema in the TypeScript package.
pub(all) struct OpenAICompatibleImageModelOptions {
  size : String?
  quality : String?
  output_format : String?
  output_compression : Int?
  background : String?
  extensions : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct and validate typed OpenAI-compatible image options.
pub fn OpenAICompatibleImageModelOptions::new(
  size? : String,
  quality? : String,
  output_format? : String,
  output_compression? : Int,
  background? : String,
  extensions? : Map[String, Json] = Map([]),
) -> OpenAICompatibleImageModelOptions raise {
  guard output_compression is None ||
    (output_compression.unwrap() >= 0 && output_compression.unwrap() <= 100) else {
    fail("OpenAI-compatible image output_compression must be between 0 and 100")
  }
  { size, quality, output_format, output_compression, background, extensions }
}

///|
/// Convert image options to a provider namespace.
pub fn OpenAICompatibleImageModelOptions::to_provider_options(
  self : OpenAICompatibleImageModelOptions,
  provider_name? : String = "openaiCompatible",
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  for entry in self.extensions.iter2() {
    values[entry.0] = entry.1
  }
  if self.size is Some(value) {
    values["size"] = Json::string(value)
  }
  if self.quality is Some(value) {
    values["quality"] = Json::string(value)
  }
  if self.output_format is Some(value) {
    values["output_format"] = Json::string(value)
  }
  if self.output_compression is Some(value) {
    values["output_compression"] = Json::number(value.to_double())
  }
  if self.background is Some(value) {
    values["background"] = Json::string(value)
  }
  compatible_namespaced_options(provider_name, values)
}

///|
/// OpenAI-compatible models follow AI SDK's provider-name convention: only
/// the segment before the first dot participates in provider options.
fn compatible_provider_options_name(provider_name : String) -> String {
  let segments = provider_name.trim().split(".").collect()
  if segments.length() == 0 {
    ""
  } else {
    segments[0].trim().to_owned()
  }
}

///|
fn resolve_compatible_options(
  options : Map[String, Json],
  provider_name : String,
  reserved_fields : Array[String],
) -> @provider_utils.ProviderOptionsResolution {
  let options_name = compatible_provider_options_name(provider_name)
  let generic = @provider_utils.resolve_provider_options(
    options,
    provider_name="openai-compatible.chat",
    reserved_fields~,
  )
  let specific = @provider_utils.resolve_provider_options(
    options,
    provider_name=options_name,
    reserved_fields~,
  )
  if generic.namespace_key is Some(key) && specific.namespace_key == Some(key) {
    return specific
  }
  if generic.namespace_key is Some(_) || specific.namespace_key is Some(_) {
    return @provider_utils.merge_provider_options_resolutions(generic, specific)
  }
  @provider_utils.resolve_provider_options(
    options,
    provider_name=options_name,
    aliases=["openaiCompatible", "openai-compatible"],
    reserved_fields~,
  )
}

///|
priv struct OpenAICompatibleChatOptions {
  user : String?
  reasoning_effort : String?
  text_verbosity : String?
  strict_json_schema : Bool?
  extensions : Map[String, Json]
}

///|
priv struct ParsedOpenAICompatibleChatOptions {
  options : OpenAICompatibleChatOptions
  warnings : Array[@provider.Warning]
}

///|
priv struct OpenAICompatiblePreparedChatRequest {
  body : Json
  warnings : Array[@provider.Warning]
  metadata_key : String
}

///|
fn parse_compatible_chat_options(
  options : @provider.ChatCallOptions,
  provider_name : String,
) -> ParsedOpenAICompatibleChatOptions {
  let resolution = resolve_compatible_options(
    options.provider_options,
    provider_name,
    chat_reserved_fields(),
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let user = reader.take_string("user")
  let reasoning_effort = reader.take_string("reasoningEffort", aliases=[
    "reasoning_effort",
  ])
  let text_verbosity = reader.take_string("textVerbosity", aliases=["verbosity"])
  let strict_json_schema = reader.take_bool("strictJsonSchema", aliases=[
    "strict_json_schema",
  ])
  {
    options: {
      user,
      reasoning_effort,
      text_verbosity,
      strict_json_schema,
      extensions: reader.remaining_values(),
    },
    warnings: reader.diagnostics(),
  }
}

///|
fn chat_reserved_fields() -> Array[String] {
  [
    "model", "messages", "stream", "stream_options", "max_tokens", "temperature",
    "top_p", "frequency_penalty", "presence_penalty", "seed", "stop", "tools", "tool_choice",
    "response_format",
  ]
}

///|
fn completion_reserved_fields() -> Array[String] {
  [
    "model", "prompt", "stream", "stream_options", "max_tokens", "temperature", "top_p",
    "frequency_penalty", "presence_penalty", "seed", "stop",
  ]
}

///|
fn embedding_reserved_fields() -> Array[String] {
  ["model", "input", "encoding_format"]
}

///|
fn image_reserved_fields() -> Array[String] {
  ["model", "prompt", "image", "mask", "n", "response_format"]
}

///|
/// Image generation settings shared by the compatible and official OpenAI
/// adapters. The wire protocol has no portable fields for these options, so
/// callers get an explicit warning when they would otherwise be discarded.
fn compatible_image_request_warnings(
  options : @provider.ImageCallOptions,
  resolution : @provider_utils.ProviderOptionsResolution,
) -> Array[@provider.Warning] {
  let warnings = resolution.warnings.copy()
  if options.aspect_ratio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="OpenAI image generation uses size instead of aspectRatio.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="OpenAI image generation does not support seed.",
      ),
    )
  }
  warnings
}

///|
fn openai_compatible_reasoning_effort(
  effort : @provider.ReasoningEffort,
) -> String? {
  match effort {
    @provider.ProviderDefault | @provider.Disabled => None
    @provider.Minimal => Some("minimal")
    @provider.Low => Some("low")
    @provider.Medium => Some("medium")
    @provider.High => Some("high")
    @provider.XHigh => Some("xhigh")
  }
}

///|
fn compatible_chat_request_warnings(
  options : @provider.ChatCallOptions,
  parsed : ParsedOpenAICompatibleChatOptions,
  supports_structured_outputs : Bool,
  supports_top_k : Bool,
  supports_frequency_penalty : Bool,
) -> Array[@provider.Warning] {
  let warnings = parsed.warnings.copy()
  if !supports_top_k && options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="OpenAI-compatible Chat Completions does not define a portable top-k field.",
      ),
    )
  }
  if !supports_frequency_penalty && options.frequency_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="frequencyPenalty",
        details="This OpenAI-compatible provider does not support frequencyPenalty.",
      ),
    )
  }
  for tool in options.tools {
    match tool {
      @provider.ProviderTool(id~, ..) =>
        warnings.push(
          @provider.Warning::Unsupported(
            feature="provider-defined tool \{id}",
            details="OpenAI-compatible Chat Completions accepts function tools only.",
          ),
        )
      _ => ()
    }
  }
  if options.response_format is @provider.JsonResponse({ schema: Some(_), .. }) &&
    !supports_structured_outputs {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="responseFormat",
        details="JSON Schema requires supports_structured_outputs; using json_object instead.",
      ),
    )
  }
  warnings
}

///|
fn compatible_completion_request_warnings(
  options : @provider.CompletionOptions,
  resolution : @provider_utils.ProviderOptionsResolution,
) -> Array[@provider.Warning] {
  let warnings = resolution.warnings.copy()
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="OpenAI-compatible Completions does not define a portable top-k field.",
      ),
    )
  }
  warnings
}

///|
fn prepare_compatible_chat_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  preserve_reasoning : Bool,
  include_usage : Bool,
  stream : Bool,
  provider_name : String,
  supports_structured_outputs : Bool,
  supports_top_k : Bool,
  supports_frequency_penalty : Bool,
  prompt_converter : OpenAICompatiblePromptConverter,
) -> OpenAICompatiblePreparedChatRequest raise {
  let parsed = parse_compatible_chat_options(options, provider_name)
  let conversion = prompt_converter(
    options.messages,
    preserve_reasoning,
    provider_name,
  )
  let warnings = compatible_chat_request_warnings(
    options, parsed, supports_structured_outputs, supports_top_k, supports_frequency_penalty,
  )
  for warning in conversion.warnings {
    warnings.push(warning)
  }
  {
    body: encode_chat_request_with_options(
      model_id,
      options,
      conversion.messages,
      parsed.options,
      include_usage,
      stream,
      supports_structured_outputs,
      supports_top_k,
      supports_frequency_penalty,
    ),
    warnings,
    metadata_key: @provider_utils.resolve_provider_options_key(
      compatible_provider_options_name(provider_name),
      options.provider_options,
    ),
  }
}

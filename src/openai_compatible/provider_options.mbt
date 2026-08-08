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
  let generic = resolve_compatible_namespace_pair(
    options, "openai-compatible", reserved_fields,
  )
  if options_name == "openai-compatible" {
    return generic
  }
  let specific = resolve_compatible_namespace_pair(
    options, options_name, reserved_fields,
  )
  @provider_utils.merge_provider_options_resolutions(generic, specific)
}

///|
fn resolve_compatible_exact_namespace(
  options : Map[String, Json],
  namespace_key : String,
  reserved_fields : Array[String],
) -> @provider_utils.ProviderOptionsResolution {
  let scoped : Map[String, Json] = Map([])
  if options.get(namespace_key) is Some(value) {
    scoped[namespace_key] = value
  }
  @provider_utils.resolve_provider_options(
    scoped,
    provider_name=namespace_key,
    reserved_fields~,
    prefer_exact_provider_name=true,
  )
}

///|
/// AI SDK merges a provider's raw namespace with its camel-case spelling.
/// Fields from the camel-case object win while distinct raw fields survive.
fn resolve_compatible_namespace_pair(
  options : Map[String, Json],
  raw_name : String,
  reserved_fields : Array[String],
) -> @provider_utils.ProviderOptionsResolution {
  let raw = resolve_compatible_exact_namespace(
    options, raw_name, reserved_fields,
  )
  let camel_name = @provider_utils.provider_options_camel_case(raw_name)
  if camel_name == raw_name {
    return raw
  }
  if options.get(raw_name) is Some(value) && !(value is Null) {
    raw.warnings.push(
      @provider.Warning::Deprecated(
        setting="providerOptions key '\{raw_name}'",
        message="Use '\{camel_name}' instead.",
      ),
    )
  }
  let camel = resolve_compatible_exact_namespace(
    options, camel_name, reserved_fields,
  )
  @provider_utils.merge_provider_options_resolutions(raw, camel)
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
  aspect_ratio : String?,
  seed : Int?,
  resolution : @provider_utils.ProviderOptionsResolution,
) -> Array[@provider.Warning] {
  let warnings = resolution.warnings.copy()
  if aspect_ratio is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="aspectRatio",
        details="This model does not support aspect ratio. Use `size` instead.",
      ),
    )
  }
  if seed is Some(_) {
    warnings.push(@provider.Warning::unsupported("seed"))
  }
  warnings
}

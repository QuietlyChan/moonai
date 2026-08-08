///|
/// Detail object returned by a standard OpenAI-compatible error response.
pub(all) struct OpenAICompatibleErrorDetail {
  message : String
  error_type : String?
  param : Json?
  code : Json?
} derive(Debug, Eq)

///|
/// Construct one OpenAI-compatible error detail object.
pub fn OpenAICompatibleErrorDetail::new(
  message~ : String,
  error_type? : String,
  param? : Json,
  code? : Json,
) -> OpenAICompatibleErrorDetail {
  { message, error_type, param, code }
}

///|
/// Structured error payload exported by the OpenAI-compatible provider.
pub(all) struct OpenAICompatibleErrorData {
  error : OpenAICompatibleErrorDetail
} derive(Debug, Eq)

///|
/// Decode the standard nested OpenAI-compatible error payload.
fn decode_openai_compatible_error_data(
  json : Json,
) -> OpenAICompatibleErrorData? {
  match json {
    { "error": Object(fields) as detail, .. } =>
      match @provider_utils.json_string_field(detail, "message") {
        Some(message) =>
          Some({
            error: OpenAICompatibleErrorDetail::new(
              message~,
              error_type?=@provider_utils.json_string_field(detail, "type"),
              param?=fields.get("param"),
              code?=fields.get("code"),
            ),
          })
        None => None
      }
    _ => None
  }
}

///|
/// Provider-specific error handling for OpenAI-compatible endpoints.
///
/// `error_to_message` also acts as the lightweight schema boundary used by
/// MoonBit providers: returning `None` means that the JSON value does not match
/// the configured error shape. `is_retryable` can override the normal HTTP
/// status based retry decision for a parsed error response.
pub struct OpenAICompatibleErrorStructure {
  priv error_to_message_callback : (Json) -> String? raise
  priv is_retryable_callback : (Int, Json?) -> Bool? raise
}

///|
/// AI SDK name for the configurable provider error schema boundary.
pub type ProviderErrorStructure = OpenAICompatibleErrorStructure

///|
/// Create a provider error structure.
pub fn OpenAICompatibleErrorStructure::new(
  error_to_message~ : (Json) -> String? raise,
  is_retryable? : (Int, Json?) -> Bool? raise = default_retryable_override,
) -> OpenAICompatibleErrorStructure {
  {
    error_to_message_callback: error_to_message,
    is_retryable_callback: is_retryable,
  }
}

///|
fn default_retryable_override(
  _status_code : Int,
  _error : Json?,
) -> Bool? raise {
  // Adapt the pure built-in callback to the fallible transport hook contract.
  @provider.check_cancellation(None)
  None
}

///|
fn default_compatible_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match decode_openai_compatible_error_data(json) {
    Some(data) => Some(data.error.message)
    None =>
      match json {
        { "error": String(message), .. } => Some(message)
        { "type": "error", "message": String(message), .. } => Some(message)
        _ => None
      }
  }
}

///|
/// Return the permissive OpenAI-compatible error structure used by default.
fn default_openai_compatible_error_structure() -> OpenAICompatibleErrorStructure {
  OpenAICompatibleErrorStructure::new(
    error_to_message=default_compatible_error_message,
  )
}

///|
fn OpenAICompatibleErrorStructure::message(
  self : OpenAICompatibleErrorStructure,
  json : Json,
) -> String? raise {
  (self.error_to_message_callback)(json)
}

///|
fn OpenAICompatibleErrorStructure::retryable(
  self : OpenAICompatibleErrorStructure,
  status_code : Int,
  error : Json?,
) -> Bool? raise {
  (self.is_retryable_callback)(status_code, error)
}

///|
/// Stateful metadata collector created for one streaming response.
pub struct OpenAICompatibleStreamMetadataExtractor {
  priv process_chunk_callback : (Json) -> Unit
  priv build_metadata_callback : () -> Map[String, Json]
}

///|
/// Create a stateful streaming metadata collector.
pub fn OpenAICompatibleStreamMetadataExtractor::new(
  process_chunk~ : (Json) -> Unit,
  build_metadata~ : () -> Map[String, Json],
) -> OpenAICompatibleStreamMetadataExtractor {
  {
    process_chunk_callback: process_chunk,
    build_metadata_callback: build_metadata,
  }
}

///|
fn OpenAICompatibleStreamMetadataExtractor::process_chunk(
  self : OpenAICompatibleStreamMetadataExtractor,
  chunk : Json,
) -> Unit {
  (self.process_chunk_callback)(chunk)
}

///|
fn OpenAICompatibleStreamMetadataExtractor::build_metadata(
  self : OpenAICompatibleStreamMetadataExtractor,
) -> Map[String, Json] {
  @provider.copy_provider_metadata((self.build_metadata_callback)())
}

///|
/// Provider metadata extraction hooks for complete and streaming chat
/// responses. A fresh stream extractor is created for every request so state
/// is never shared between concurrent model calls.
pub struct OpenAICompatibleMetadataExtractor {
  priv extract_metadata_callback : (Json) -> Map[String, Json]
  priv create_stream_extractor_callback : () -> OpenAICompatibleStreamMetadataExtractor
}

///|
/// AI SDK name for OpenAI-compatible provider metadata hooks.
pub type MetadataExtractor = OpenAICompatibleMetadataExtractor

///|
/// Create provider-specific metadata extraction hooks.
pub fn OpenAICompatibleMetadataExtractor::new(
  extract_metadata~ : (Json) -> Map[String, Json],
  create_stream_extractor~ : () -> OpenAICompatibleStreamMetadataExtractor,
) -> OpenAICompatibleMetadataExtractor {
  {
    extract_metadata_callback: extract_metadata,
    create_stream_extractor_callback: create_stream_extractor,
  }
}

///|
/// Extract metadata from one complete response.
pub fn OpenAICompatibleMetadataExtractor::extract_metadata(
  self : OpenAICompatibleMetadataExtractor,
  response : Json,
) -> Map[String, Json] {
  @provider.copy_provider_metadata((self.extract_metadata_callback)(response))
}

///|
fn OpenAICompatibleMetadataExtractor::create_stream_extractor(
  self : OpenAICompatibleMetadataExtractor,
) -> OpenAICompatibleStreamMetadataExtractor {
  (self.create_stream_extractor_callback)()
}

///|
/// Provider-specific conversion hook for optional token accounting payloads.
pub type OpenAICompatibleUsageConverter = (Json?) -> @provider.LanguageModelV4Usage

///|
/// Successful JSON/SSE schema boundary used before compatible response
/// mapping. Returning a message rejects the value as a stream error or typed
/// invalid response.
pub type OpenAICompatibleJsonValidator = (Json) -> String?

///|
/// Convert the standard OpenAI-compatible usage object to the V4 usage shape.
/// Providers can replace this function through `convert_usage` when their
/// accounting semantics differ.
pub fn convert_openai_compatible_chat_usage(
  usage : Json?,
) -> @provider.LanguageModelV4Usage {
  match usage {
    Some(json) if !(json is Null) => {
      let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
      let output_tokens = @provider_utils.json_int_field(
        json, "completion_tokens",
      )
      let reasoning_tokens = match json {
        {
          "completion_tokens_details": {
            "reasoning_tokens": Number(value, ..),
            ..
          },
          ..
        } => value.to_int()
        _ => 0
      }
      let cached_input_tokens = match json {
        {
          "prompt_tokens_details": { "cached_tokens": Number(value, ..), .. },
          ..
        } => value.to_int()
        _ => 0
      }
      {
        input_tokens: {
          total: Some(input_tokens),
          no_cache: Some(input_tokens - cached_input_tokens),
          cache_read: Some(cached_input_tokens),
          cache_write: None,
        },
        output_tokens: {
          total: Some(output_tokens),
          text: Some(output_tokens - reasoning_tokens),
          reasoning: Some(reasoning_tokens),
        },
        raw: Some(json),
      }
    }
    _ => @provider_utils.create_null_language_model_usage()
  }
}

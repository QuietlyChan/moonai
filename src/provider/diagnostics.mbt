///|
/// The exact HTTP request sent to a provider.
///
/// Headers can contain credentials. Applications should redact them before
/// writing this value to logs or telemetry.
pub(all) struct RequestMetadata {
  url : String
  headers : Map[String, String]
  body : String
} derive(Debug, Eq)

///|
/// Construct request metadata from the final serialized request body.
pub fn RequestMetadata::new(
  url~ : String,
  headers~ : Map[String, String],
  body~ : String,
) -> RequestMetadata {
  { url, headers, body }
}

///|
/// HTTP response information retained for diagnostics and telemetry.
///
/// Streaming responses do not buffer their complete body. In that case
/// `body` is `None`; callers can opt into `StreamEvent::Raw` to inspect the
/// individual provider chunks.
pub(all) struct ResponseMetadata {
  id : String?
  model_id : String?
  created_at : Int?
  status_code : Int?
  headers : Map[String, String]
  body : String?
} derive(Debug, Eq)

///|
/// Return an empty response metadata value for deterministic/mock models.
pub fn ResponseMetadata::empty() -> ResponseMetadata {
  {
    id: None,
    model_id: None,
    created_at: None,
    status_code: None,
    headers: Map([]),
    body: None,
  }
}

///|
/// Construct response metadata from an HTTP response and optional provider
/// response identifiers.
pub fn ResponseMetadata::new(
  id? : String,
  model_id? : String,
  created_at? : Int,
  status_code? : Int,
  headers? : Map[String, String] = Map([]),
  body? : String,
) -> ResponseMetadata {
  { id, model_id, created_at, status_code, headers, body }
}

///|
/// Return whether this metadata value contains no transport or provider data.
pub fn ResponseMetadata::is_empty(self : ResponseMetadata) -> Bool {
  self.id is None &&
  self.model_id is None &&
  self.created_at is None &&
  self.status_code is None &&
  self.headers.length() == 0 &&
  self.body is None
}

///|
/// A warning produced while adapting a provider-neutral request.
pub(all) enum Warning {
  Unsupported(feature~ : String, details~ : String)
  Compatibility(feature~ : String, details~ : String)
  Deprecated(setting~ : String, message~ : String)
  Other(message~ : String)
} derive(Debug, Eq)

///|
/// Raised when a file reference has no identifier for the requested provider.
pub suberror NoSuchProviderReferenceError {
  NoSuchProviderReferenceError(
    provider~ : String,
    available_providers~ : Array[String]
  )
} derive(Debug)

///|
/// A provider API call failure, including invalid successful responses.
///
/// This mirrors AI SDK's structured API call error boundary. Credentials can
/// be present in `request_headers`; callers should redact them before logging.
/// `status_code` is `None` when the transport never received an HTTP response.
pub(all) suberror APICallError {
  APICallError(
    message~ : String,
    url~ : String,
    request_body~ : String,
    request_headers~ : Map[String, String],
    status_code~ : Int?,
    response_headers~ : Map[String, String],
    response_body~ : String,
    is_retryable~ : Bool,
    data~ : Json?,
    cause~ : String?
  )
} derive(Debug)

///|
/// Raised when a response or event payload cannot be parsed as JSON.
///
/// MoonBit JSON values do not have JavaScript prototypes, so the security
/// filtering in AI SDK's `secureJsonParse` is unnecessary here. The typed
/// parse boundary and original text are still preserved.
pub(all) suberror JSONParseError {
  JSONParseError(text~ : String, cause~ : String)
} derive(Debug, Eq)

///|
/// Construct a JSON parse error from the original text and parser diagnostic.
pub fn JSONParseError::new(text~ : String, cause~ : String) -> JSONParseError {
  JSONParseError(text~, cause~)
}

///|
/// Return the AI SDK-style human-readable JSON parse diagnostic.
pub fn JSONParseError::message(self : JSONParseError) -> String {
  match self {
    JSONParseError(text~, cause~) =>
      "JSON parsing failed: Text: \{text}.\nError message: \{cause}"
  }
}

///|
/// Optional location and entity information for a type validation failure.
pub(all) struct TypeValidationContext {
  field : String?
  entity_name : String?
  entity_id : String?
} derive(Debug, Eq)

///|
/// Construct validation context using AI SDK's field/entity vocabulary.
pub fn TypeValidationContext::new(
  field? : String,
  entity_name? : String,
  entity_id? : String,
) -> TypeValidationContext {
  { field, entity_name, entity_id }
}

///|
/// Raised when a parsed JSON value does not satisfy a typed boundary.
pub(all) suberror TypeValidationError {
  TypeValidationError(
    value~ : Json,
    cause~ : String,
    context~ : TypeValidationContext?
  )
} derive(Debug)

///|
/// Construct a typed validation error.
pub fn TypeValidationError::new(
  value~ : Json,
  cause~ : String,
  context? : TypeValidationContext,
) -> TypeValidationError {
  TypeValidationError(value~, cause~, context~)
}

///|
/// Return the AI SDK-style human-readable type validation diagnostic.
pub fn TypeValidationError::message(self : TypeValidationError) -> String {
  match self {
    TypeValidationError(value~, cause~, context~) => {
      let mut prefix = "Type validation failed"
      match context {
        Some(value) => {
          if value.field is Some(field) {
            prefix = prefix + " for " + field
          }
          let entities : Array[String] = []
          if value.entity_name is Some(name) {
            entities.push(name)
          }
          if value.entity_id is Some(id) {
            entities.push("id: \"" + id + "\"")
          }
          if entities.length() > 0 {
            prefix = prefix + " (" + entities.join(", ") + ")"
          }
        }
        None => ()
      }
      prefix + ": Value: " + value.stringify() + ".\nError message: " + cause
    }
  }
}

///|
/// Raised when a streaming HTTP response has no readable body.
pub(all) suberror EmptyResponseBodyError {
  EmptyResponseBodyError(message~ : String)
} derive(Debug, Eq)

///|
/// Construct an empty-body error with AI SDK's default message.
pub fn EmptyResponseBodyError::new(
  message? : String = "Empty response body",
) -> EmptyResponseBodyError {
  EmptyResponseBodyError(message~)
}

///|
/// Raised when a provider completes without generating any content.
pub(all) suberror NoContentGeneratedError {
  NoContentGeneratedError(message~ : String)
} derive(Debug, Eq)

///|
/// Construct a no-content error with AI SDK's default message.
pub fn NoContentGeneratedError::new(
  message? : String = "No content generated.",
) -> NoContentGeneratedError {
  NoContentGeneratedError(message~)
}

///|
/// Raised when a caller supplies an invalid high-level option.
///
/// Keeping the argument name separate from the message mirrors AI SDK's
/// `InvalidArgumentError` and lets wrappers report the failing boundary
/// without parsing human-readable text.
pub(all) suberror InvalidArgumentError {
  InvalidArgumentError(argument~ : String, message~ : String)
} derive(Debug, Eq)

///|
/// Raised when high-level prompt input violates the provider-neutral prompt
/// contract before any provider request is prepared.
pub(all) suberror InvalidPromptError {
  InvalidPromptError(message~ : String)
} derive(Debug, Eq)

///|
/// Model family requested from a provider factory.
pub(all) enum NoSuchModelType {
  LanguageModel
  EmbeddingModel
  ImageModel
  TranscriptionModel
  SpeechModel
  RerankingModel
  VideoModel
} derive(Debug, Eq)

///|
/// Raised when a provider factory cannot create the requested model.
///
/// This error belongs to the provider contract, matching AI SDK's
/// `NoSuchModelError` ownership in `@ai-sdk/provider`.
pub(all) suberror NoSuchModelError {
  NoSuchModelError(model_id~ : String, model_type~ : NoSuchModelType)
} derive(Debug, Eq)

///|
/// Return the requested provider-specific model identifier.
pub fn NoSuchModelError::model_id(self : NoSuchModelError) -> String {
  match self {
    NoSuchModelError(model_id~, ..) => model_id
  }
}

///|
/// Return the requested provider model family.
pub fn NoSuchModelError::model_type(self : NoSuchModelError) -> NoSuchModelType {
  match self {
    NoSuchModelError(model_type~, ..) => model_type
  }
}

///|
/// Raised when a client-executed tool call has no matching result in a
/// normalized prompt.
///
/// Prompt preparation owns the validation, while the shared provider package
/// owns the error so every high-level entry point can expose one stable type.
pub(all) suberror MissingToolResultsError {
  MissingToolResultsError(tool_call_ids~ : Array[String])
} derive(Debug, Eq)

///|
/// Raised when a provider API key cannot be resolved from the explicit
/// setting or its configured environment variable.
pub(all) suberror LoadAPIKeyError {
  LoadAPIKeyError(
    environment_variable_name~ : String,
    api_key_parameter_name~ : String,
    description~ : String,
    message~ : String
  )
} derive(Debug, Eq)

///|
/// Raised when a provider setting cannot be resolved from the explicit
/// setting or its configured environment variable.
pub(all) suberror LoadSettingError {
  LoadSettingError(
    environment_variable_name~ : String,
    setting_name~ : String,
    description~ : String,
    message~ : String
  )
} derive(Debug, Eq)

///|
/// Raised when a provider returns a successful HTTP response with invalid
/// protocol data.
pub(all) suberror InvalidResponseDataError {
  InvalidResponseDataError(message~ : String, data~ : Json)
} derive(Debug)

///|
/// Raised when a provider-side asynchronous operation exceeds its polling
/// deadline after the HTTP transport itself remained healthy.
///
/// Keeping this separate from `APICallError` distinguishes a task that is
/// still running from an HTTP response that the provider rejected. It also
/// lets callers decide whether to resume polling or surface a timeout.
pub(all) suberror ProviderTimeoutError {
  ProviderTimeoutError(
    provider~ : String,
    operation~ : String,
    timeout_ms~ : Int
  )
} derive(Debug, Eq)

///|
/// Raised when a provider adapter cannot represent a requested capability.
///
/// This is the MoonBit counterpart of AI SDK's
/// `UnsupportedFunctionalityError`. Unlike an unsupported-option warning,
/// this error is used when silently dropping the capability would change the
/// meaning of the request.
pub(all) suberror UnsupportedFunctionalityError {
  UnsupportedFunctionalityError(functionality~ : String)
} derive(Debug)

///|
/// Raised when an embedding call exceeds the model's per-call batch limit.
///
/// AI SDK exposes this as a typed error so callers can distinguish a local
/// batching mistake from a provider-side API failure. Keeping the original
/// values makes the error useful to retry or split at an application boundary.
pub(all) suberror TooManyEmbeddingValuesForCallError {
  TooManyEmbeddingValuesForCallError(
    provider~ : String,
    model_id~ : String,
    max_embeddings_per_call~ : Int,
    values~ : Array[String]
  )
} derive(Debug, Eq)

///|
/// Resolve a provider-specific file identifier or raise a typed error.
pub fn resolve_provider_reference(
  reference : ProviderReference,
  provider : String,
) -> String raise NoSuchProviderReferenceError {
  match reference.get(provider) {
    Some(id) => id
    None =>
      raise NoSuchProviderReferenceError(
        provider~,
        available_providers=reference.providers(),
      )
  }
}

///|
/// Create an unsupported-feature warning without additional details.
pub fn Warning::unsupported(feature : String) -> Warning {
  Unsupported(feature~, details="")
}

///|
/// Create a compatibility warning without additional details.
pub fn Warning::compatibility(feature : String) -> Warning {
  Compatibility(feature~, details="")
}

///|
/// Retry configuration used by provider transports.
///
/// `max_retries` counts retries after the initial request. The default policy
/// follows the AI SDK convention of two retries with exponential backoff.
pub(all) struct RetryPolicy {
  max_retries : Int
  initial_delay_ms : Int
  max_delay_ms : Int
  backoff_factor : Double
} derive(Debug)

///|
/// Construct a validated retry policy.
pub fn RetryPolicy::new(
  max_retries? : Int = 2,
  initial_delay_ms? : Int = 200,
  max_delay_ms? : Int = 10_000,
  backoff_factor? : Double = 2.0,
) -> RetryPolicy raise {
  guard max_retries >= 0 else { fail("retry max_retries must be >= 0") }
  guard initial_delay_ms >= 0 else {
    fail("retry initial_delay_ms must be >= 0")
  }
  guard max_delay_ms >= 0 else { fail("retry max_delay_ms must be >= 0") }
  guard backoff_factor >= 1.0 else { fail("retry backoff_factor must be >= 1") }
  { max_retries, initial_delay_ms, max_delay_ms, backoff_factor }
}

///|
/// Return the AI SDK-compatible default retry policy.
pub fn RetryPolicy::standard() -> RetryPolicy {
  {
    max_retries: 2,
    initial_delay_ms: 200,
    max_delay_ms: 10_000,
    backoff_factor: 2.0,
  }
}

///|
/// Disable retries.
pub fn RetryPolicy::none() -> RetryPolicy {
  { max_retries: 0, initial_delay_ms: 0, max_delay_ms: 0, backoff_factor: 1.0 }
}

///|
/// Return whether this policy can issue another request after a failure.
pub fn RetryPolicy::can_retry(self : RetryPolicy, retry_number : Int) -> Bool {
  retry_number < self.max_retries
}

///|
/// Cooperative cancellation signal for provider calls.
///
/// Cancelling a token does not interrupt a non-async computation, but the
/// built-in HTTP transport checks it before requests, between retries, and
/// between stream chunks. Cancelling the enclosing MoonBit async task remains
/// the stronger way to interrupt a socket read immediately.
pub struct CancellationToken {
  priv cancelled : Ref[Bool]
} derive(Debug)

///|
/// Error raised when a cancellation token is cancelled.
pub suberror CancellationError derive(Debug)

///|
/// Create a fresh cancellation token.
pub fn CancellationToken::new() -> CancellationToken {
  { cancelled: Ref(false) }
}

///|
/// Cancel all operations observing this token.
pub fn CancellationToken::cancel(self : CancellationToken) -> Unit {
  self.cancelled.val = true
}

///|
/// Return whether this token has been cancelled.
pub fn CancellationToken::is_cancelled(self : CancellationToken) -> Bool {
  self.cancelled.val
}

///|
/// Raise `CancellationError` when this token is cancelled.
pub fn CancellationToken::check(self : CancellationToken) -> Unit raise {
  if self.is_cancelled() {
    raise CancellationError
  }
}

///|
/// Check an optional token at an async operation boundary.
pub fn check_cancellation(token : CancellationToken?) -> Unit raise {
  match token {
    Some(value) => value.check()
    None => ()
  }
}

///|
/// Copy a provider metadata map without sharing its mutable storage.
pub fn copy_provider_metadata(
  metadata : Map[String, Json],
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in metadata.iter2() {
    let (key, value) = entry
    result[key] = value
  }
  result
}

///|
/// Copy a warning list.
pub fn copy_warnings(warnings : Array[Warning]) -> Array[Warning] {
  [
    for warning in warnings => warning
  ]
}

///|
/// Merge two provider metadata maps. Values from `extra` replace values with
/// the same provider key.
pub fn merge_provider_metadata(
  base : Map[String, Json],
  extra : Map[String, Json],
) -> Map[String, Json] {
  let result = copy_provider_metadata(base)
  for entry in extra.iter2() {
    let (key, value) = entry
    result[key] = match result.get(key) {
      Some(Object(existing)) if value is Object(_) => {
        let merged : Map[String, Json] = Map([])
        for existing_entry in existing.iter2() {
          let (existing_key, existing_value) = existing_entry
          merged[existing_key] = existing_value
        }
        match value {
          Object(incoming) =>
            for incoming_entry in incoming.iter2() {
              let (incoming_key, incoming_value) = incoming_entry
              merged[incoming_key] = incoming_value
            }
          _ => ()
        }
        Json::object(merged)
      }
      _ => value
    }
  }
  result
}

///|
/// Merge response metadata while preserving provider-specific fields that may
/// have been collected by a streaming decoder.
pub fn merge_response_metadata(
  base : ResponseMetadata?,
  transport : ResponseMetadata,
) -> ResponseMetadata {
  match base {
    None => transport
    Some(value) =>
      {
        id: match value.id {
          Some(_) => value.id
          None => transport.id
        },
        model_id: match value.model_id {
          Some(_) => value.model_id
          None => transport.model_id
        },
        created_at: match value.created_at {
          Some(_) => value.created_at
          None => transport.created_at
        },
        status_code: match transport.status_code {
          Some(_) => transport.status_code
          None => value.status_code
        },
        headers: if transport.headers.length() > 0 {
          transport.headers
        } else {
          value.headers
        },
        body: match transport.body {
          Some(_) => transport.body
          None => value.body
        },
      }
  }
}

///|
/// Merge an optional response metadata value, ignoring empty values.
pub fn merge_optional_response_metadata(
  base : ResponseMetadata?,
  extra : ResponseMetadata?,
) -> ResponseMetadata? {
  match extra {
    None => base
    Some(value) if value.is_empty() => base
    Some(value) => Some(merge_response_metadata(base, value))
  }
}

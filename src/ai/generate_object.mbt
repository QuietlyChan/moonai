///|
/// A parsed structured output together with its normalized model response.
pub(all) struct ObjectResponse {
  object : Json
  response : @provider.LanguageModelV4GenerateResult
} derive(Debug)

///|
/// A schema validation failure raised by the high-level structured-output API.
///
/// `provider_utils` owns the draft-independent validator. This error keeps
/// the public `ai` boundary independent from that implementation package and
/// gives callers a stable path/message pair for diagnostics.
pub suberror ObjectValidationError {
  ObjectValidationError(path~ : String, message~ : String)
} derive(Debug, Eq)

///|
/// The reason a structured-output call could not produce a validated object.
pub(all) enum ObjectGenerationFailure {
  EmptyResponse
  InvalidJson(message~ : String)
  SchemaMismatch(path~ : String, message~ : String)
} derive(Debug, Eq)

///|
/// Raised when a model does not return a JSON value matching the requested
/// schema. The raw response is retained so callers can inspect or repair it.
pub suberror NoObjectGeneratedError {
  NoObjectGeneratedError(
    message~ : String,
    text~ : String?,
    response~ : @provider.LanguageModelV4GenerateResult,
    failure~ : ObjectGenerationFailure
  )
} derive(Debug)

///|
/// Validate a JSON value against a structured-output schema.
pub fn validate_object(
  schema : Json,
  value : Json,
) -> Unit raise ObjectValidationError {
  try @provider_utils.validate_json_schema(schema, value) catch {
    @provider_utils.JsonSchemaValidationError(path~, message~) =>
      raise ObjectValidationError(path~, message~)
  } noraise {
    _ => ()
  }
}

///|
/// AI SDK-style camel-case spelling for `validate_object`.
pub fn validateObject(
  schema : Json,
  value : Json,
) -> Unit raise ObjectValidationError {
  validate_object(schema, value)
}

///|
/// Generate and parse one JSON object constrained by a JSON Schema.
pub async fn generate_object(
  model : &@provider.LanguageModelV4,
  schema : Json,
  prompt? : String,
  messages? : Array[ModelMessage] = [],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
  name? : String,
  description? : String,
  reasoning_effort? : ReasoningEffort = ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  experimental_download? : DownloadFunction,
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ObjectResponse {
  let response = generate_text(
    model,
    prompt?,
    messages~,
    instructions?,
    allow_system_in_messages~,
    response_format=ResponseFormat::json(schema~, name?, description?),
    reasoning_effort~,
    max_output_tokens?,
    temperature?,
    top_p?,
    top_k?,
    frequency_penalty?,
    presence_penalty?,
    seed?,
    stop_sequences~,
    headers~,
    provider_options~,
    experimental_download?,
    retry_policy~,
    cancellation_token?,
  )
  let text = response.text()
  if text == "" {
    raise NoObjectGeneratedError(
      message="No object generated: the model did not return a response.",
      text=None,
      response~,
      failure=EmptyResponse,
    )
  }
  let object = try @json.parse(text) catch {
    error =>
      raise NoObjectGeneratedError(
        message="No object generated: could not parse the response.",
        text=Some(text),
        response~,
        failure=InvalidJson(message=@debug.to_string(error)),
      )
  } noraise {
    value => value
  }
  try validate_object(schema, object) catch {
    ObjectValidationError(path~, message~) =>
      raise NoObjectGeneratedError(
        message="No object generated: response did not match schema.",
        text=Some(text),
        response~,
        failure=SchemaMismatch(path~, message~),
      )
  } noraise {
    _ => ()
  }
  { object, response }
}

///|
/// AI SDK-style camel-case spelling for `generate_object`.
pub async fn generateObject(
  model : &@provider.LanguageModelV4,
  schema : Json,
  prompt? : String,
  messages? : Array[ModelMessage] = [],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
  name? : String,
  description? : String,
  reasoning_effort? : ReasoningEffort = ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  experimental_download? : DownloadFunction,
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ObjectResponse {
  generate_object(
    model,
    schema,
    prompt?,
    messages~,
    instructions?,
    allow_system_in_messages~,
    name?,
    description?,
    reasoning_effort~,
    max_output_tokens?,
    temperature?,
    top_p?,
    top_k?,
    frequency_penalty?,
    presence_penalty?,
    seed?,
    stop_sequences~,
    headers~,
    provider_options~,
    experimental_download?,
    retry_policy~,
    cancellation_token?,
  )
}

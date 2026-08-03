///|
/// A parsed structured output together with its normalized model response.
pub(all) struct ObjectResponse {
  object : Json
  response : ChatResponse
} derive(Debug)

///|
/// Generate and parse one JSON object constrained by a JSON Schema.
pub async fn generate_object(
  model : &ChatModel,
  schema : Json,
  prompt? : String,
  messages? : Array[Message] = [],
  name? : String = "response",
  strict? : Bool = true,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ObjectResponse {
  let response = generate_text(
    model,
    prompt?,
    messages~,
    response_format=JsonSchema(name~, schema~, strict~),
    max_output_tokens?,
    temperature?,
    top_p?,
    frequency_penalty?,
    presence_penalty?,
    seed?,
    stop_sequences~,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
  let object = @json.parse(response.text) catch {
    error =>
      fail(
        "structured output is not valid JSON: \{error}; text: \{response.text}",
      )
  }
  { object, response }
}

///|
/// Camel-case compatibility alias for AI SDK's `generateObject`.
pub async fn generateObject(
  model : &ChatModel,
  schema : Json,
  prompt? : String,
  messages? : Array[Message] = [],
  name? : String = "response",
  strict? : Bool = true,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ObjectResponse {
  generate_object(
    model,
    schema,
    prompt?,
    messages~,
    name~,
    strict~,
    max_output_tokens?,
    temperature?,
    top_p?,
    frequency_penalty?,
    presence_penalty?,
    seed?,
    stop_sequences~,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

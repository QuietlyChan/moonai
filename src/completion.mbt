///|
/// Options shared by provider-neutral legacy completion calls.
pub(all) struct CompletionOptions {
  prompt : String
  suffix : String?
  max_output_tokens : Int?
  temperature : Double?
  top_p : Double?
  frequency_penalty : Double?
  presence_penalty : Double?
  seed : Int?
  stop_sequences : Array[String]
  include_raw_chunks : Bool
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct normalized completion options.
pub fn CompletionOptions::new(
  prompt : String,
  suffix? : String,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> CompletionOptions {
  {
    prompt,
    suffix,
    max_output_tokens,
    temperature,
    top_p,
    frequency_penalty,
    presence_penalty,
    seed,
    stop_sequences,
    include_raw_chunks,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Accumulated result returned by a completion model.
pub(all) struct CompletionResponse {
  text : String
  usage : Usage
  finish_reason : FinishReason
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a completion response without transport diagnostics.
pub fn CompletionResponse::new(
  text : String,
  usage : Usage,
  finish_reason : FinishReason,
) -> CompletionResponse {
  {
    text,
    usage,
    finish_reason,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach diagnostics to a completion result.
pub fn CompletionResponse::with_diagnostics(
  self : CompletionResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> CompletionResponse {
  {
    text: self.text,
    usage: self.usage,
    finish_reason: self.finish_reason,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add HTTP metadata to a completion result.
pub fn CompletionResponse::with_transport(
  self : CompletionResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> CompletionResponse {
  {
    text: self.text,
    usage: self.usage,
    finish_reason: self.finish_reason,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}

///|
/// Generate a completion without streaming.
pub async fn complete(
  model : &CompletionModel,
  prompt : String,
  suffix? : String,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> CompletionResponse {
  check_cancellation(cancellation_token)
  model.generate(
    CompletionOptions::new(
      prompt,
      suffix?,
      max_output_tokens?,
      temperature?,
      top_p?,
      frequency_penalty?,
      presence_penalty?,
      seed?,
      stop_sequences~,
      include_raw_chunks~,
      headers~,
      provider_options~,
      retry_policy~,
      cancellation_token?,
    ),
  )
}

///|
/// Stream a legacy completion using the shared normalized text events.
pub async fn stream_completion(
  model : &CompletionModel,
  prompt : String,
  suffix? : String,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  on_event? : async (StreamEvent) -> Unit = _ => (),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> CompletionResponse {
  check_cancellation(cancellation_token)
  model.stream(
    CompletionOptions::new(
      prompt,
      suffix?,
      max_output_tokens?,
      temperature?,
      top_p?,
      frequency_penalty?,
      presence_penalty?,
      seed?,
      stop_sequences~,
      include_raw_chunks~,
      headers~,
      provider_options~,
      retry_policy~,
      cancellation_token?,
    ),
    on_event,
  )
}

///|
/// Generate a completion without streaming.
pub async fn complete(
  model : &CompletionModel,
  prompt : String,
  suffix? : String,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
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
      top_k?,
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
/// Stream an OpenAI-style legacy `/completions` wire model.
pub async fn stream_completion(
  model : &CompletionModel,
  prompt : String,
  suffix? : String,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
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
      top_k?,
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

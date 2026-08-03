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
  }
}

///|
/// Accumulated result returned by a completion model.
pub(all) struct CompletionResponse {
  text : String
  usage : Usage
  finish_reason : FinishReason
} derive(Debug, Eq)

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
) -> CompletionResponse {
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
) -> CompletionResponse {
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
    ),
    on_event,
  )
}

///|
fn prepare_chat_call_options(
  prompt : String?,
  messages : Array[Message],
  tools : Array[ToolDefinition],
  tool_choice : ToolChoice,
  response_format : ResponseFormat,
  max_output_tokens : Int?,
  temperature : Double?,
  top_p : Double?,
  frequency_penalty : Double?,
  presence_penalty : Double?,
  seed : Int?,
  stop_sequences : Array[String],
  include_raw_chunks : Bool,
  headers : Map[String, String],
  provider_options : Map[String, Json],
  retry_policy : RetryPolicy,
  cancellation_token : CancellationToken?,
) -> ChatCallOptions raise {
  let all_messages = messages.copy()
  if prompt is Some(text) {
    all_messages.push(Message::user(text))
  }
  guard all_messages.length() > 0 else {
    fail("text generation requires prompt or messages")
  }
  ChatCallOptions::new(
    all_messages,
    tools~,
    tool_choice~,
    response_format~,
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
  )
}

///|
/// Generate text with a provider-neutral model using a non-streaming request.
pub async fn generate_text(
  model : &ChatModel,
  prompt? : String,
  messages? : Array[Message] = [],
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
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
) -> ChatResponse {
  check_cancellation(cancellation_token)
  model.generate(
    prepare_chat_call_options(
      prompt, messages, tools, tool_choice, response_format, max_output_tokens, temperature,
      top_p, frequency_penalty, presence_penalty, seed, stop_sequences, include_raw_chunks,
      headers, provider_options, retry_policy, cancellation_token,
    ),
  )
}

///|
/// Camel-case compatibility alias for AI SDK's `generateText`.
pub async fn generateText(
  model : &ChatModel,
  prompt? : String,
  messages? : Array[Message] = [],
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
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
) -> ChatResponse {
  check_cancellation(cancellation_token)
  generate_text(
    model,
    prompt?,
    messages~,
    tools~,
    tool_choice~,
    response_format~,
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
  )
}

///|
/// Stream text with a provider-neutral model.
///
/// This is the MoonBit equivalent of AI SDK's `streamText`: provider packages
/// implement `ChatModel`, while this function owns the user-facing options.
pub async fn stream_text(
  model : &ChatModel,
  prompt? : String,
  messages? : Array[Message] = [],
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
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
) -> ChatResponse {
  check_cancellation(cancellation_token)
  model.stream(
    prepare_chat_call_options(
      prompt, messages, tools, tool_choice, response_format, max_output_tokens, temperature,
      top_p, frequency_penalty, presence_penalty, seed, stop_sequences, include_raw_chunks,
      headers, provider_options, retry_policy, cancellation_token,
    ),
    on_event,
  )
}

///|
/// Camel-case compatibility alias for developers coming from TypeScript.
pub async fn streamText(
  model : &ChatModel,
  prompt? : String,
  messages? : Array[Message] = [],
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
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
) -> ChatResponse {
  check_cancellation(cancellation_token)
  stream_text(
    model,
    prompt?,
    messages~,
    tools~,
    tool_choice~,
    response_format~,
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
    on_event~,
    retry_policy~,
    cancellation_token?,
  )
}

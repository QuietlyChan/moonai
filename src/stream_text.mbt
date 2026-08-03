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
  stop_sequences? : Array[String] = [],
  provider_options? : Map[String, Json] = Map([]),
  on_event? : async (StreamEvent) -> Unit = _ => (),
) -> ChatResponse {
  let all_messages = messages.copy()
  if prompt is Some(text) {
    all_messages.push(Message::user(text))
  }
  guard all_messages.length() > 0 else {
    fail("stream_text requires prompt or messages")
  }
  model.stream(
    ChatCallOptions::new(
      all_messages,
      tools~,
      tool_choice~,
      response_format~,
      max_output_tokens?,
      temperature?,
      top_p?,
      stop_sequences~,
      provider_options~,
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
  stop_sequences? : Array[String] = [],
  provider_options? : Map[String, Json] = Map([]),
  on_event? : async (StreamEvent) -> Unit = _ => (),
) -> ChatResponse {
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
    stop_sequences~,
    provider_options~,
    on_event~,
  )
}

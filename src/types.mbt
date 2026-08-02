///|
/// A provider-neutral chat message role.
pub(all) enum Role {
  System
  User
  Assistant
  Tool(String)
} derive(Debug, Eq)

///|
/// Convert a role to the OpenAI wire name.
pub fn Role::to_openai_string(self : Role) -> String {
  match self {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool(_) => "tool"
  }
}

///|
/// A function tool advertised to a language model.
pub(all) struct ToolDefinition {
  name : String
  description : String
  parameters : Json
  strict : Bool
} derive(Debug)

///|
/// Construct a tool definition.
pub fn ToolDefinition::new(
  name : String,
  description : String,
  parameters : Json,
  strict? : Bool = false,
) -> ToolDefinition {
  { name, description, parameters, strict }
}

///|
/// One complete model-generated function call.
pub(all) struct ToolCall {
  id : String
  name : String
  arguments : String
} derive(Debug, Eq)

///|
/// Construct a complete tool call.
pub fn ToolCall::new(
  id~ : String,
  name~ : String,
  arguments~ : String,
) -> ToolCall {
  { id, name, arguments }
}

///|
/// A provider-neutral chat message.
pub(all) struct Message {
  role : Role
  content : String
  tool_calls : Array[ToolCall]
  reasoning_content : String?
} derive(Debug, Eq)

///|
/// Construct a message with optional tool and reasoning data.
pub fn Message::new(
  role : Role,
  content~ : String,
  tool_calls? : Array[ToolCall] = [],
  reasoning_content? : String,
) -> Message {
  { role, content, tool_calls, reasoning_content }
}

///|
/// Construct a system message.
pub fn Message::system(content : String) -> Message {
  Message::new(System, content~)
}

///|
/// Construct a user message.
pub fn Message::user(content : String) -> Message {
  Message::new(User, content~)
}

///|
/// Construct an assistant message.
pub fn Message::assistant(
  content : String,
  tool_calls? : Array[ToolCall] = [],
  reasoning_content? : String,
) -> Message {
  Message::new(Assistant, content~, tool_calls~, reasoning_content?)
}

///|
/// Construct a tool-result message.
pub fn Message::tool(tool_call_id : String, content : String) -> Message {
  Message::new(Tool(tool_call_id), content~)
}

///|
/// Standard token accounting returned by providers.
pub(all) struct Usage {
  input_tokens : Int
  output_tokens : Int
  total_tokens : Int
  reasoning_tokens : Int
  cached_input_tokens : Int
} derive(Debug, Eq)

///|
/// Return zero token usage.
pub fn Usage::zero() -> Usage {
  {
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
  }
}

///|
/// Why the model stopped generating.
pub(all) enum FinishReason {
  Stop
  Length
  ToolCalls
  ContentFilter
  Error
  Unknown(String)
} derive(Debug, Eq)

///|
/// Normalize an OpenAI finish reason.
pub fn FinishReason::from_openai(value : String) -> FinishReason {
  match value {
    "stop" => Stop
    "length" => Length
    "tool_calls" => ToolCalls
    "content_filter" => ContentFilter
    "error" => Error
    other => Unknown(other)
  }
}

///|
/// How a provider should select from the advertised tools.
pub(all) enum ToolChoice {
  Auto
  NoTool
  Required
  Named(String)
} derive(Debug, Eq)

///|
/// Standardized response format request.
pub(all) enum ResponseFormat {
  Text
  JsonObject
  JsonSchema(name~ : String, schema~ : Json, strict~ : Bool)
} derive(Debug)

///|
/// Provider-neutral options passed to a chat model.
pub(all) struct ChatCallOptions {
  messages : Array[Message]
  tools : Array[ToolDefinition]
  tool_choice : ToolChoice
  response_format : ResponseFormat
  max_output_tokens : Int?
  temperature : Double?
  top_p : Double?
  stop_sequences : Array[String]
  provider_options : Map[String, Json]
} derive(Debug)

///|
/// Construct normalized chat call options.
pub fn ChatCallOptions::new(
  messages : Array[Message],
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  stop_sequences? : Array[String] = [],
  provider_options? : Map[String, Json] = Map([]),
) -> ChatCallOptions {
  {
    messages,
    tools,
    tool_choice,
    response_format,
    max_output_tokens,
    temperature,
    top_p,
    stop_sequences,
    provider_options,
  }
}

///|
/// A fully accumulated streaming response.
pub(all) struct ChatResponse {
  text : String
  reasoning : String
  tool_calls : Array[ToolCall]
  usage : Usage
  finish_reason : FinishReason
} derive(Debug, Eq)

///|
/// Return an empty accumulated response.
pub fn ChatResponse::empty() -> ChatResponse {
  {
    text: "",
    reasoning: "",
    tool_calls: [],
    usage: Usage::zero(),
    finish_reason: Unknown(""),
  }
}

///|
/// The stable event protocol emitted by all streaming providers.
pub(all) enum StreamEvent {
  StreamStart
  TextStart(String)
  TextDelta(id~ : String, delta~ : String)
  TextEnd(String)
  ReasoningStart(String)
  ReasoningDelta(id~ : String, delta~ : String)
  ReasoningEnd(String)
  ToolInputStart(id~ : String, tool_name~ : String)
  ToolInputDelta(id~ : String, delta~ : String)
  ToolInputEnd(String)
  ToolCallReady(ToolCall)
  Finish(usage~ : Usage, reason~ : FinishReason)
  Raw(Json)
  StreamError(String)
} derive(Debug)

///|
/// Receives lifecycle events emitted by the reusable example tools.
pub type ToolEventSink = async (Json) -> Unit

///|
async fn emit_tool_event(
  sink : ToolEventSink,
  kind : String,
  name : String,
  tool_call_id : String,
  payload : Json,
) -> Unit {
  sink({
    "type": kind,
    "toolName": name,
    "toolCallId": tool_call_id,
    "payload": payload,
  })
}

///|
async fn execute_calculator(
  input : Json,
  options : @provider_utils.ToolExecutionOptions,
  sink : ToolEventSink,
) -> Json {
  emit_tool_event(
    sink,
    "tool-execution-start",
    "calculator",
    options.tool_call_id,
    input,
  )
  let output : Json = match input {
    {
      "operation": String(operation),
      "a": Number(a, ..),
      "b": Number(b, ..),
      ..
    } =>
      match operation {
        "add" => { "result": a + b }
        "subtract" => { "result": a - b }
        "multiply" => { "result": a * b }
        "divide" if b != 0.0 => { "result": a / b }
        "divide" => { "error": "division by zero" }
        _ => { "error": "unsupported operation" }
      }
    _ => { "error": "operation, a, and b are required" }
  }
  emit_tool_event(
    sink,
    "tool-execution-result",
    "calculator",
    options.tool_call_id,
    output,
  )
  output
}

///|
async fn execute_weather(
  input : Json,
  options : @provider_utils.ToolExecutionOptions,
  sink : ToolEventSink,
) -> Json {
  emit_tool_event(
    sink,
    "tool-execution-start",
    "get_weather",
    options.tool_call_id,
    input,
  )
  let city = match input {
    { "city": String(value), .. } => value
    _ => "Unknown"
  }
  let output : Json = {
    "city": city,
    "condition": "clear",
    "temperatureC": 24,
    "humidityPercent": 61,
    "source": "example fixture",
  }
  emit_tool_event(
    sink,
    "tool-execution-result",
    "get_weather",
    options.tool_call_id,
    output,
  )
  output
}

///|
async fn execute_moonai_search(
  input : Json,
  options : @provider_utils.ToolExecutionOptions,
  sink : ToolEventSink,
) -> Json {
  emit_tool_event(
    sink,
    "tool-execution-start",
    "search_moonai",
    options.tool_call_id,
    input,
  )
  let query = match input {
    { "query": String(value), .. } => value
    _ => "MoonAI"
  }
  let output : Json = {
    "query": query,
    "results": [
      {
        "title": "Provider-neutral V4 models",
        "summary": "One language-model contract supports OpenAI, Anthropic, DeepSeek, Alibaba, MiniMax, and compatible endpoints.",
      },
      {
        "title": "High-level agent loop",
        "summary": "generate_text and stream_text validate inputs, execute tools, and aggregate multi-step usage.",
      },
    ],
  }
  emit_tool_event(
    sink,
    "tool-execution-result",
    "search_moonai",
    options.tool_call_id,
    output,
  )
  output
}

///|
/// Create the local tools used by both CLI and browser examples.
pub fn example_tools(
  sink? : ToolEventSink = _event => (),
) -> @provider_utils.ToolSet {
  @provider_utils.tool_set([
    (
      "calculator",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": {
            "operation": {
              "type": "string",
              "enum": ["add", "subtract", "multiply", "divide"],
            },
            "a": { "type": "number" },
            "b": { "type": "number" },
          },
          "required": ["operation", "a", "b"],
          "additionalProperties": false,
        },
        description="Perform a basic arithmetic operation.",
        strict=true,
        execute=(input, options) => execute_calculator(input, options, sink),
      ),
    ),
    (
      "get_weather",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
          "additionalProperties": false,
        },
        description="Get deterministic example weather for a city.",
        strict=true,
        execute=(input, options) => execute_weather(input, options, sink),
      ),
    ),
    (
      "search_moonai",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "query": { "type": "string" } },
          "required": ["query"],
          "additionalProperties": false,
        },
        description="Search the bundled MoonAI example knowledge base.",
        strict=true,
        execute=(input, options) => execute_moonai_search(input, options, sink),
      ),
    ),
  ])
}

///|
/// Convert V4 usage to a compact JSON shape for HTTP and CLI examples.
pub fn usage_json(usage : @provider.LanguageModelV4Usage) -> Json {
  {
    "inputTokens": usage.input_tokens.total.unwrap_or(0),
    "outputTokens": usage.output_tokens.total.unwrap_or(0),
    "totalTokens": usage.input_tokens.total.unwrap_or(0) +
    usage.output_tokens.total.unwrap_or(0),
  }
}

///|
priv struct AnthropicWireMessage {
  role : String
  content : Array[Json]
}

///|
fn text_content(text : String) -> Json {
  { "type": "text", "text": text }
}

///|
fn AnthropicWireMessage::to_json(self : AnthropicWireMessage) -> Json {
  Json::object(
    Map([
      ("role", Json::string(self.role)),
      ("content", Json::array(self.content)),
    ]),
  )
}

///|
fn append_wire_message(
  messages : Array[AnthropicWireMessage],
  role : String,
  content : Array[Json],
) -> Unit {
  guard content.length() > 0 else { return }
  if messages.length() > 0 && messages[messages.length() - 1].role == role {
    let existing = messages[messages.length() - 1].content
    for part in content {
      existing.push(part)
    }
  } else {
    messages.push({ role, content })
  }
}

///|
fn tool_input(call : @moonai.ToolCall) -> Json raise {
  if call.arguments.trim().is_empty() {
    return Json::empty_object()
  }
  let input = @json.parse(call.arguments) catch {
    error =>
      fail(
        "Anthropic tool call \{call.name} has invalid JSON arguments: \{error}",
      )
  }
  guard input is Object(_) else {
    fail("Anthropic tool call \{call.name} arguments must be a JSON object")
  }
  input
}

///|
fn assistant_content(message : @moonai.Message) -> Array[Json] raise {
  let content : Array[Json] = []
  if message.content != "" {
    content.push(text_content(message.content))
  }
  for call in message.tool_calls {
    content.push({
      "type": "tool_use",
      "id": call.id,
      "name": call.name,
      "input": tool_input(call),
    })
  }
  if content.length() == 0 {
    content.push(text_content(""))
  }
  content
}

///|
fn tool_result_content(tool_call_id : String, content : String) -> Json {
  Json::object(
    Map([
      ("type", Json::string("tool_result")),
      ("tool_use_id", Json::string(tool_call_id)),
      ("content", Json::array([text_content(content)])),
    ]),
  )
}

///|
fn tool_definition_to_json(tool : @moonai.ToolDefinition) -> Json {
  Json::object(
    Map(
      [
        ("name", Json::string(tool.name)),
        ("description", Json::string(tool.description)),
        ("input_schema", tool.parameters),
        ..if tool.strict {
          [("strict", Json::boolean(true))]
        },
      ],
    ),
  )
}

///|
fn tool_choice_to_json(choice : @moonai.ToolChoice) -> Json {
  match choice {
    @moonai.Auto => { "type": "auto" }
    @moonai.Required => { "type": "any" }
    @moonai.Named(name) => { "type": "tool", "name": name }
    @moonai.NoTool => { "type": "auto" }
  }
}

///|
fn response_output_config(format : @moonai.ResponseFormat) -> Json? {
  match format {
    @moonai.Text => None
    @moonai.JsonObject => None
    @moonai.JsonSchema(schema~, ..) =>
      Some(({ "format": { "type": "json_schema", "schema": schema } } : Json))
  }
}

///|
/// Anthropic accepts temperatures in the inclusive range 0..1.
fn normalized_temperature(value : Double) -> Double {
  if value > 1.0 {
    1.0
  } else if value < 0.0 {
    0.0
  } else {
    value
  }
}

///|
/// Encode normalized call options as an Anthropic Messages request.
pub fn encode_messages_request(
  model_id : String,
  options : @moonai.ChatCallOptions,
) -> Json raise {
  let system : Array[Json] = []
  let messages : Array[AnthropicWireMessage] = []
  for message in options.messages {
    match message.role {
      @moonai.System => system.push(text_content(message.content))
      @moonai.User =>
        append_wire_message(messages, "user", [text_content(message.content)])
      @moonai.Assistant =>
        append_wire_message(messages, "assistant", assistant_content(message))
      @moonai.Tool(tool_call_id) =>
        append_wire_message(messages, "user", [
          tool_result_content(tool_call_id, message.content),
        ])
    }
  }
  let include_tools = options.tools.length() > 0 &&
    !(options.tool_choice is @moonai.NoTool)
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      (
        "messages",
        Json::array([ for message in messages => message.to_json() ]),
      ),
      (
        "max_tokens",
        Json::number(options.max_output_tokens.unwrap_or(4096).to_double()),
      ),
      ("stream", Json::boolean(true)),
      ..if system.length() > 0 {
        [("system", Json::array(system))]
      },
      ..if options.temperature is Some(value) {
        [("temperature", Json::number(normalized_temperature(value)))]
      },
      ..if options.top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if options.stop_sequences.length() > 0 {
        [
          (
            "stop_sequences",
            Json::array(
              [
                for stop in options.stop_sequences => Json::string(stop)
              ],
            ),
          ),
        ]
      },
      ..if include_tools {
        [
          (
            "tools",
            Json::array(
              [
                for tool in options.tools => tool_definition_to_json(tool)
              ],
            ),
          ),
          ("tool_choice", tool_choice_to_json(options.tool_choice)),
        ]
      },
      ..if response_output_config(options.response_format) is Some(config) {
        [("output_config", config)]
      },
    ],
  )
  for entry in options.provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}

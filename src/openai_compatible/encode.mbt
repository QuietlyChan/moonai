///|
fn tool_call_to_json(call : @moonai.ToolCall) -> Json {
  {
    "id": call.id,
    "type": "function",
    "function": { "name": call.name, "arguments": call.arguments },
  }
}

///|
fn message_to_json(
  message : @moonai.Message,
  preserve_reasoning : Bool,
) -> Json {
  let content = match message.role {
    @moonai.Assistant if message.tool_calls.length() > 0 &&
      message.content == "" => Json::null()
    _ => Json::string(message.content)
  }
  Json::object(
    Map(
      [
        ("role", Json::string(message.role.to_openai_string())),
        ("content", content),
        ..if message.role is @moonai.Tool(tool_call_id) {
          [("tool_call_id", Json::string(tool_call_id))]
        },
        ..if message.tool_calls.length() > 0 {
          [
            (
              "tool_calls",
              Json::array(
                [
                  for call in message.tool_calls => tool_call_to_json(call)
                ],
              ),
            ),
          ]
        },
        ..if preserve_reasoning &&
          message.role is @moonai.Assistant &&
          message.reasoning_content is Some(reasoning) {
          [("reasoning_content", Json::string(reasoning))]
        },
      ],
    ),
  )
}

///|
fn tool_definition_to_json(tool : @moonai.ToolDefinition) -> Json {
  let function = Json::object(
    Map(
      [
        ("name", Json::string(tool.name)),
        ("description", Json::string(tool.description)),
        ("parameters", tool.parameters),
        ..if tool.strict {
          [("strict", Json::boolean(true))]
        },
      ],
    ),
  )
  { "type": "function", "function": function }
}

///|
fn tool_choice_to_json(choice : @moonai.ToolChoice) -> Json {
  match choice {
    @moonai.Auto => Json::string("auto")
    @moonai.NoTool => Json::string("none")
    @moonai.Required => Json::string("required")
    @moonai.Named(name) => { "type": "function", "function": { "name": name } }
  }
}

///|
fn response_format_to_json(format : @moonai.ResponseFormat) -> Json? {
  match format {
    @moonai.Text => None
    @moonai.JsonObject => Some(({ "type": "json_object" } : Json))
    @moonai.JsonSchema(name~, schema~, strict~) =>
      Some(
        (
          {
            "type": "json_schema",
            "json_schema": { "name": name, "schema": schema, "strict": strict },
          } : Json),
      )
  }
}

///|
/// Encode normalized options as an OpenAI-compatible Chat Completions request.
pub fn encode_chat_request(
  model_id : String,
  options : @moonai.ChatCallOptions,
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
) -> Json {
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      (
        "messages",
        Json::array(
          [
            for message in options.messages => {
              message_to_json(message, preserve_reasoning)
            }
          ],
        ),
      ),
      ("stream", Json::boolean(true)),
      ..if include_usage {
        [("stream_options", ({ "include_usage": true } : Json))]
      },
      ..if options.max_output_tokens is Some(value) {
        [("max_tokens", Json::number(value.to_double()))]
      },
      ..if options.temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if options.top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if options.stop_sequences.length() > 0 {
        [
          (
            "stop",
            Json::array(
              [
                for stop in options.stop_sequences => Json::string(stop)
              ],
            ),
          ),
        ]
      },
      ..if options.tools.length() > 0 {
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
      ..if response_format_to_json(options.response_format) is Some(format) {
        [("response_format", format)]
      },
    ],
  )
  for entry in options.provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}

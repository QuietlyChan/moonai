///|
fn input_text(text : String) -> Json {
  { "type": "input_text", "text": text }
}

///|
fn data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}

///|
fn content_part_to_responses_input(part : @moonai.ContentPart) -> Json raise {
  match part {
    @moonai.Text(value) => input_text(value)
    @moonai.ImageUrl(url) => { "type": "input_image", "image_url": url }
    @moonai.ImageData(data~, media_type~) =>
      { "type": "input_image", "image_url": data_uri(media_type, data) }
    @moonai.FileData(data~, media_type~, filename~) =>
      {
        "type": "input_file",
        "filename": filename,
        "file_data": data_uri(media_type, data),
      }
    @moonai.AudioData(..) =>
      fail("Open Responses does not accept audio content in this adapter")
  }
}

///|
fn output_text(text : String) -> Json {
  { "type": "output_text", "text": text }
}

///|
fn message_item(role : String, content : Array[Json]) -> Json {
  Json::object(
    Map([
      ("type", Json::string("message")),
      ("role", Json::string(role)),
      ("content", Json::array(content)),
    ]),
  )
}

///|
fn message_parts(parts : Array[@moonai.ContentPart]) -> Array[Json] raise {
  [
    for part in parts => content_part_to_responses_input(part)
  ]
}

///|
fn tool_definition_to_json(tool : @moonai.ToolDefinition) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("function")),
        ("name", Json::string(tool.name)),
        ("description", Json::string(tool.description)),
        ("parameters", tool.parameters),
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
    @moonai.Auto => Json::string("auto")
    @moonai.NoTool => Json::string("none")
    @moonai.Required => Json::string("required")
    @moonai.Named(name) => { "type": "function", "name": name }
  }
}

///|
fn text_format_to_json(format : @moonai.ResponseFormat) -> Json? {
  match format {
    @moonai.Text => None
    @moonai.JsonObject => Some(({ "format": { "type": "json_object" } } : Json))
    @moonai.JsonSchema(name~, schema~, strict~) =>
      Some(
        (
          {
            "format": {
              "type": "json_schema",
              "name": name,
              "schema": schema,
              "strict": strict,
            },
          } : Json),
      )
  }
}

///|
/// Convert normalized messages into Open Responses input items.
fn convert_messages(
  messages : Array[@moonai.Message],
) -> (Array[Json], String?) raise {
  let input : Array[Json] = []
  let instructions : Array[String] = []
  for message in messages {
    match message.role {
      @moonai.System =>
        if message.parts.length() > 0 {
          for part in message.parts {
            match part {
              @moonai.Text(value) => instructions.push(value)
              _ => fail("Open Responses system messages support text only")
            }
          }
        } else {
          instructions.push(message.content)
        }
      @moonai.User =>
        input.push(
          message_item(
            "user",
            if message.parts.length() > 0 {
              message_parts(message.parts)
            } else {
              [input_text(message.content)]
            },
          ),
        )
      @moonai.Assistant => {
        if message.content != "" || message.parts.length() > 0 {
          input.push(
            message_item(
              "assistant",
              if message.parts.length() > 0 {
                [
                  for part in message.parts => {
                    match part {
                      @moonai.Text(value) => output_text(value)
                      _ =>
                        fail(
                          "Open Responses assistant messages support text only",
                        )
                    }
                  }
                ]
              } else {
                [output_text(message.content)]
              },
            ),
          )
        }
        for call in message.tool_calls {
          input.push({
            "type": "function_call",
            "call_id": call.id,
            "name": call.name,
            "arguments": call.arguments,
          })
        }
      }
      @moonai.Tool(tool_call_id) =>
        input.push({
          "type": "function_call_output",
          "call_id": tool_call_id,
          "output": message.content,
        })
    }
  }
  let system = if instructions.length() == 0 {
    None
  } else {
    Some(instructions.join("\n"))
  }
  (input, system)
}

///|
/// Encode normalized options as an Open Responses request.
pub fn encode_responses_request(
  model_id : String,
  options : @moonai.ChatCallOptions,
  stream? : Bool = true,
) -> Json raise {
  let (input, instructions) = convert_messages(options.messages)
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("input", Json::array(input)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if instructions is Some(value) {
        [("instructions", Json::string(value))]
      },
      ..if options.max_output_tokens is Some(value) {
        [("max_output_tokens", Json::number(value.to_double()))]
      },
      ..if options.temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if options.top_p is Some(value) {
        [("top_p", Json::number(value))]
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
      ..if text_format_to_json(options.response_format) is Some(text) {
        [("text", text)]
      },
    ],
  )
  for entry in options.provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}

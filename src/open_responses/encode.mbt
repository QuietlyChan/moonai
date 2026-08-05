///|
fn input_text(text : String) -> Json {
  { "type": "input_text", "text": text }
}

///|
fn data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}

///|
fn content_part_to_responses_input(
  part : @provider.LanguageModelContentPart,
) -> Json raise {
  match part.without_provider_options() {
    @provider.Text(value) => input_text(value)
    @provider.ImageUrl(url) => { "type": "input_image", "image_url": url }
    @provider.ImageData(data~, media_type~) => {
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      { "type": "input_image", "image_url": data_uri(full_media_type, data) }
    }
    @provider.FileUrl(url~, media_type~, filename=_) =>
      if @provider_utils.get_top_level_media_type(media_type) == "image" {
        { "type": "input_image", "image_url": url }
      } else {
        { "type": "input_file", "file_url": url }
      }
    @provider.FileData(data~, media_type~, filename~) => {
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      if @provider_utils.get_top_level_media_type(media_type) == "image" {
        { "type": "input_image", "image_url": data_uri(full_media_type, data) }
      } else {
        {
          "type": "input_file",
          "filename": if filename == "" {
            "data"
          } else {
            filename
          },
          "file_data": data_uri(full_media_type, data),
        }
      }
    }
    @provider.FileReference(..) =>
      fail("Open Responses does not accept file provider references")
    @provider.AudioData(..) =>
      fail("Open Responses does not accept audio content in this adapter")
    @provider.Reasoning(_)
    | @provider.ReasoningFileUrl(..)
    | @provider.ReasoningFileData(..)
    | @provider.Custom(..)
    | @provider.ToolCallPart(_)
    | @provider.ToolResultPart(_)
    | @provider.ToolApprovalRequestPart(_)
    | @provider.ToolApprovalResponsePart(_) =>
      fail("Open Responses does not accept this content part in a user message")
    @provider.ProviderOptions(part~, ..) =>
      content_part_to_responses_input(part)
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
fn message_parts(
  parts : Array[@provider.LanguageModelContentPart],
) -> Array[Json] raise {
  [
    for part in parts => content_part_to_responses_input(part)
  ]
}

///|
fn tool_message_parts(
  parts : Array[@provider.LanguageModelContentPart],
) -> Array[Json] raise {
  let converted : Array[Json] = []
  for part in parts {
    match part.without_provider_options() {
      @provider.FileReference(..) | @provider.AudioData(..) => ()
      _ => converted.push(content_part_to_responses_input(part))
    }
  }
  converted
}

///|
fn tool_result_content_part_to_responses(
  part : @provider.LanguageModelToolResultContentPart,
) -> Json raise {
  match part {
    @provider.LanguageModelToolText(text~, ..) => input_text(text)
    @provider.LanguageModelToolFileUrl(url~, media_type~, ..) =>
      if @provider_utils.get_top_level_media_type(media_type) == "image" {
        { "type": "input_image", "image_url": url }
      } else {
        { "type": "input_file", "file_url": url }
      }
    @provider.LanguageModelToolFileData(data~, media_type~, filename~, ..) => {
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      if @provider_utils.get_top_level_media_type(media_type) == "image" {
        { "type": "input_image", "image_url": data_uri(full_media_type, data) }
      } else {
        {
          "type": "input_file",
          "filename": if filename == "" {
            "data"
          } else {
            filename
          },
          "file_data": data_uri(full_media_type, data),
        }
      }
    }
    @provider.LanguageModelToolFileReference(..) =>
      fail("Open Responses tool result content does not accept file references")
    @provider.LanguageModelToolCustom(..) =>
      fail("Open Responses tool result content does not accept custom parts")
  }
}

///|
/// Convert a structured tool-result output to the string/content form used by
/// Open Responses function_call_output items.
fn tool_result_output_to_responses(
  output : @provider.LanguageModelToolResultOutput,
) -> Json raise {
  match output {
    @provider.LanguageModelToolTextOutput(value~, ..)
    | @provider.LanguageModelToolErrorText(value~, ..) => Json::string(value)
    @provider.LanguageModelToolJsonOutput(value~, ..)
    | @provider.LanguageModelToolErrorJson(value~, ..) =>
      Json::string(value.stringify())
    @provider.LanguageModelToolExecutionDenied(reason~, ..) =>
      Json::string(reason.unwrap_or("Tool call execution denied."))
    @provider.LanguageModelToolContent(value~, ..) =>
      Json::array(
        [
          for part in value => tool_result_content_part_to_responses(part)
        ],
      )
  }
}

///|
fn tool_result_to_responses_output(
  result : @provider.LanguageModelToolResult,
) -> Json raise {
  {
    "type": "function_call_output",
    "call_id": result.tool_call_id,
    "output": tool_result_output_to_responses(result.output),
  }
}

///|
fn tool_approval_response_to_responses_input(
  response : @provider.LanguageModelToolApprovalResponse,
) -> Json {
  {
    "type": "mcp_approval_response",
    "approval_request_id": response.approval_id,
    "approve": response.approved,
  }
}

///|
fn tool_definition_to_json(tool : @provider.ToolDefinition) -> Json? {
  match tool {
    @provider.FunctionTool(name~, description~, input_schema~, strict~, ..) =>
      Some(
        Json::object(
          Map(
            [
              ("type", Json::string("function")),
              ("name", Json::string(name)),
              ..if description is Some(value) {
                [("description", Json::string(value))]
              },
              ("parameters", input_schema),
              ..if strict is Some(value) {
                [("strict", Json::boolean(value))]
              },
            ],
          ),
        ),
      )
    @provider.ProviderTool(..) => None
  }
}

///|
fn tool_choice_to_json(choice : @provider.ToolChoice) -> Json {
  match choice {
    @provider.Auto => Json::string("auto")
    @provider.NoTool => Json::string("none")
    @provider.Required => Json::string("required")
    @provider.Named(name) => { "type": "function", "name": name }
  }
}

///|
fn text_format_to_json(format : @provider.ResponseFormat) -> Json? {
  match format {
    @provider.Text => None
    @provider.JsonResponse(config) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("json_schema")),
      ])
      match config.schema {
        Some(schema) => {
          fields["name"] = Json::string(config.name.unwrap_or("response"))
          if config.description is Some(value) {
            fields["description"] = Json::string(value)
          }
          fields["schema"] = schema
          fields["strict"] = Json::boolean(true)
        }
        None => ()
      }
      Some(({ "format": Json::object(fields) } : Json))
    }
  }
}

///|
fn reasoning_effort_value(effort : @provider.ReasoningEffort) -> String? {
  match effort {
    @provider.ProviderDefault => None
    @provider.Disabled => Some("none")
    @provider.Minimal => Some("low")
    @provider.Low => Some("low")
    @provider.Medium => Some("medium")
    @provider.High => Some("high")
    @provider.XHigh => Some("xhigh")
  }
}

///|
fn open_responses_reasoning(
  options : @provider.ChatCallOptions,
  provider_options : OpenResponsesOptions,
) -> Json? {
  let reasoning : Map[String, Json] = Map([])
  if provider_options.reasoning_summary is Some(value) {
    reasoning["summary"] = Json::string(value)
  }
  if reasoning_effort_value(options.reasoning_effort) is Some(value) {
    reasoning["effort"] = Json::string(value)
  }
  if reasoning.length() > 0 {
    Some(Json::object(reasoning))
  } else {
    None
  }
}

///|
fn encode_responses_request_with_options(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_options : OpenResponsesOptions,
  stream : Bool,
) -> Json raise {
  let (input, instructions) = convert_messages(options.messages)
  let tools : Array[Json] = []
  for tool in options.tools {
    if tool_definition_to_json(tool) is Some(value) {
      tools.push(value)
    }
  }
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
      ..if options.frequency_penalty is Some(value) {
        [("frequency_penalty", Json::number(value))]
      },
      ..if options.presence_penalty is Some(value) {
        [("presence_penalty", Json::number(value))]
      },
      ..if open_responses_reasoning(options, provider_options) is Some(value) {
        [("reasoning", value)]
      },
    ],
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
  }
  match options.tool_choice {
    Some(choice) => fields["tool_choice"] = tool_choice_to_json(choice)
    None => ()
  }
  if text_format_to_json(options.response_format) is Some(text) {
    fields["text"] = text
  }
  Json::object(fields)
}

///|
/// Convert normalized messages into Open Responses input items.
fn convert_messages(
  messages : Array[@provider.LanguageModelMessage],
) -> (Array[Json], String?) raise {
  let input : Array[Json] = []
  let instructions : Array[String] = []
  for message in messages {
    match message.role {
      @provider.System =>
        if message.parts.length() > 0 {
          for part in message.parts {
            match part.without_provider_options() {
              @provider.Text(value) => instructions.push(value)
              _ => fail("Open Responses system messages support text only")
            }
          }
        } else {
          instructions.push(message.content)
        }
      @provider.User =>
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
      @provider.Assistant => {
        let assistant_content : Array[Json] = if message.parts.length() > 0 {
          let converted : Array[Json] = []
          for part in message.parts {
            match part.without_provider_options() {
              @provider.Text(value) => converted.push(output_text(value))
              @provider.ToolCallPart(_) => ()
              _ => fail("Open Responses assistant messages support text only")
            }
          }
          converted
        } else if message.content != "" {
          [output_text(message.content)]
        } else {
          []
        }
        if assistant_content.length() > 0 {
          input.push(message_item("assistant", assistant_content))
        }
        for call in message.effective_tool_calls() {
          input.push({
            "type": "function_call",
            "call_id": call.id,
            "name": call.name,
            "arguments": call.arguments,
          })
        }
      }
      @provider.Tool(tool_call_id) => {
        let mut structured = false
        for part in message.parts {
          match part.without_provider_options() {
            @provider.ToolResultPart(result) => {
              structured = true
              input.push(tool_result_to_responses_output(result))
            }
            @provider.ToolApprovalResponsePart(response) => {
              structured = true
              input.push(tool_approval_response_to_responses_input(response))
            }
            _ => ()
          }
        }
        if !structured {
          input.push({
            "type": "function_call_output",
            "call_id": tool_call_id,
            "output": if message.parts.length() > 0 {
              Json::array(tool_message_parts(message.parts))
            } else {
              Json::string(message.content)
            },
          })
        }
      }
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
  options : @provider.ChatCallOptions,
  stream? : Bool = true,
  provider_name? : String = "",
) -> Json raise {
  let parsed = parse_open_responses_options(options, provider_name)
  encode_responses_request_with_options(
    model_id,
    options,
    parsed.options,
    stream,
  )
}

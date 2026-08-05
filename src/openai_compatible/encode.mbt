///|
fn tool_call_thought_signature(call : @provider.ToolCall) -> String? {
  for entry in call.provider_metadata.iter2() {
    let (_, value) = entry
    match value {
      { "thoughtSignature": String(signature), .. } if signature != "" =>
        return Some(signature)
      _ => ()
    }
  }
  None
}

///|
fn openai_compatible_wire_metadata(
  options : Map[String, Json],
) -> Map[String, Json] {
  match options.get("openaiCompatible") {
    Some(Object(values)) => @provider.copy_provider_metadata(values)
    _ => Map([])
  }
}

///|
fn with_openai_compatible_wire_metadata(
  value : Json,
  options : Map[String, Json],
) -> Json {
  guard value is Object(fields) else { return value }
  let result = @provider.copy_provider_metadata(fields)
  for entry in openai_compatible_wire_metadata(options).iter2() {
    result[entry.0] = entry.1
  }
  Json::object(result)
}

///|
fn tool_call_to_json(call : @provider.ToolCall) -> Json {
  let fields : Map[String, Json] = Map([
    ("id", Json::string(call.id)),
    ("type", Json::string("function")),
    ("function", ({ "name": call.name, "arguments": call.arguments } : Json)),
  ])
  for entry in openai_compatible_wire_metadata(call.provider_metadata).iter2() {
    fields[entry.0] = entry.1
  }
  if tool_call_thought_signature(call) is Some(signature) {
    fields["extra_content"] = (
      { "google": { "thought_signature": signature } } : Json)
  }
  Json::object(fields)
}

///|
fn data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}

///|
fn content_part_to_json(
  part : @provider.LanguageModelContentPart,
  provider_name : String,
) -> Json raise {
  let content : Json = match part.without_provider_options() {
    @provider.Text(value) => { "type": "text", "text": value }
    @provider.ImageUrl(url) =>
      { "type": "image_url", "image_url": { "url": url } }
    @provider.ImageData(data~, media_type~) =>
      {
        "type": "image_url",
        "image_url": {
          "url": data_uri(
            @provider_utils.resolve_full_media_type(media_type, data),
            data,
          ),
        },
      }
    @provider.AudioData(data~, format~) =>
      {
        "type": "input_audio",
        "input_audio": { "data": data, "format": format },
      }
    @provider.FileUrl(url~, media_type~, filename=_) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      if top_level == "image" {
        { "type": "image_url", "image_url": { "url": url } }
      } else if top_level == "text" {
        { "type": "text", "text": url }
      } else if top_level == "audio" {
        fail("OpenAI-compatible Chat does not accept audio file URLs")
      } else if top_level == "application" {
        fail("OpenAI-compatible Chat does not accept PDF file URLs")
      } else {
        fail(
          "OpenAI-compatible Chat does not accept URL-backed file media type \{media_type}",
        )
      }
    }
    @provider.FileData(data~, media_type~, filename~) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      if top_level == "image" {
        {
          "type": "image_url",
          "image_url": { "url": data_uri(full_media_type, data) },
        }
      } else if top_level == "audio" {
        let format = match full_media_type {
          "audio/wav" => "wav"
          "audio/mp3" | "audio/mpeg" => "mp3"
          _ =>
            fail(
              "OpenAI-compatible Chat does not accept audio media type \{full_media_type}",
            )
        }
        {
          "type": "input_audio",
          "input_audio": { "data": data, "format": format },
        }
      } else if top_level == "application" {
        guard full_media_type == "application/pdf" else {
          fail(
            "OpenAI-compatible Chat does not accept file media type \{full_media_type}",
          )
        }
        {
          "type": "file",
          "file": {
            "filename": if filename == "" {
              "document.pdf"
            } else {
              filename
            },
            "file_data": data_uri(full_media_type, data),
          },
        }
      } else if top_level == "text" {
        { "type": "text", "text": @provider_utils.decode_base64_text(data) }
      } else {
        fail(
          "OpenAI-compatible Chat does not accept file media type \{media_type}",
        )
      }
    }
    @provider.FileReference(..) =>
      fail("OpenAI-compatible Chat does not accept file provider references")
    @provider.Reasoning(_)
    | @provider.ReasoningFileUrl(..)
    | @provider.ReasoningFileData(..)
    | @provider.Custom(..)
    | @provider.ToolCallPart(_)
    | @provider.ToolResultPart(_)
    | @provider.ToolApprovalRequestPart(_)
    | @provider.ToolApprovalResponsePart(_) =>
      fail("OpenAI-compatible Chat does not accept this content part")
    @provider.ProviderOptions(part~, ..) =>
      content_part_to_json(part, provider_name)
  }
  with_openai_compatible_wire_metadata(content, part.provider_options())
}

///|
fn compatible_assistant_content(
  message : @provider.LanguageModelMessage,
) -> String raise {
  guard message.parts.length() > 0 else { return message.content }
  let content = StringBuilder::new()
  for part in message.parts {
    match part.without_provider_options() {
      @provider.Text(value) => content.write_string(value)
      @provider.ToolCallPart(_) => ()
      _ =>
        fail(
          "OpenAI-compatible assistant messages support text content parts only",
        )
    }
  }
  content.to_string()
}

///|
fn message_to_json(
  message : @provider.LanguageModelMessage,
  preserve_reasoning : Bool,
  provider_name : String,
) -> Json raise {
  let mut metadata_options = message.provider_options
  let tool_calls = message.effective_tool_calls()
  let content = match message.role {
    @provider.User if message.parts.length() == 1 =>
      match message.parts[0].without_provider_options() {
        @provider.Text(value) => {
          metadata_options = message.parts[0].provider_options()
          Json::string(value)
        }
        _ =>
          Json::array([content_part_to_json(message.parts[0], provider_name)])
      }
    @provider.User if message.parts.length() > 0 =>
      Json::array(
        [
          for part in message.parts => content_part_to_json(part, provider_name)
        ],
      )
    @provider.Assistant => {
      let assistant_content = compatible_assistant_content(message)
      if tool_calls.length() > 0 && assistant_content == "" {
        Json::null()
      } else {
        Json::string(assistant_content)
      }
    }
    _ if message.parts.length() > 0 =>
      Json::array(
        [
          for part in message.parts => content_part_to_json(part, provider_name)
        ],
      )
    _ => Json::string(message.content)
  }
  with_openai_compatible_wire_metadata(
    Json::object(
      Map(
        [
          ("role", Json::string(message.role.to_openai_string())),
          ("content", content),
          ..if message.role is @provider.Tool(tool_call_id) {
            [("tool_call_id", Json::string(tool_call_id))]
          },
          ..if tool_calls.length() > 0 {
            [
              (
                "tool_calls",
                Json::array(
                  [
                    for call in tool_calls => tool_call_to_json(call)
                  ],
                ),
              ),
            ]
          },
          ..if preserve_reasoning &&
            message.role is @provider.Assistant &&
            message.reasoning_content is Some(reasoning) {
            [("reasoning_content", Json::string(reasoning))]
          },
        ],
      ),
    ),
    metadata_options,
  )
}

///|
/// Serialize a structured tool result for the OpenAI-compatible Chat
/// Completions contract. Compatible APIs generally accept a string in the
/// `tool` message, so non-text outputs use their provider-neutral JSON form.
fn compatible_tool_result_text(
  output : @provider.LanguageModelToolResultOutput,
) -> String {
  match output {
    @provider.LanguageModelToolTextOutput(value~, ..)
    | @provider.LanguageModelToolErrorText(value~, ..) => value
    @provider.LanguageModelToolExecutionDenied(reason~, ..) =>
      reason.unwrap_or("Tool call execution denied.")
    @provider.LanguageModelToolJsonOutput(value~, ..)
    | @provider.LanguageModelToolErrorJson(value~, ..) => value.stringify()
    @provider.LanguageModelToolContent(..) => output.to_json().stringify()
  }
}

///|
/// Expand a normalized tool message into one wire message per tool result.
/// Approval responses are intentionally ignored by Chat Completions; providers
/// that support approvals use the OpenAI Responses adapter instead.
fn message_to_json_parts(
  message : @provider.LanguageModelMessage,
  preserve_reasoning : Bool,
  provider_name : String,
) -> Array[Json] raise {
  if message.role is @provider.Tool(_) && message.parts.length() > 0 {
    let result : Array[Json] = []
    for part in message.parts {
      match part.without_provider_options() {
        @provider.ToolResultPart(tool_result) =>
          result.push(
            with_openai_compatible_wire_metadata(
              {
                "role": "tool",
                "tool_call_id": tool_result.tool_call_id,
                "content": compatible_tool_result_text(tool_result.output),
              },
              tool_result.provider_options,
            ),
          )
        @provider.ToolApprovalResponsePart(_) => ()
        _ => ()
      }
    }
    if result.length() > 0 {
      return result
    }
  }
  [message_to_json(message, preserve_reasoning, provider_name)]
}

///|
fn tool_definition_to_json(tool : @provider.ToolDefinition) -> Json? {
  match tool {
    @provider.FunctionTool(name~, description~, input_schema~, strict~, ..) => {
      let function = Json::object(
        Map(
          [
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
      )
      Some(({ "type": "function", "function": function } : Json))
    }
    @provider.ProviderTool(..) => None
  }
}

///|
fn tool_choice_to_json(choice : @provider.ToolChoice) -> Json {
  match choice {
    @provider.Auto => Json::string("auto")
    @provider.NoTool => Json::string("none")
    @provider.Required => Json::string("required")
    @provider.Named(name) =>
      { "type": "function", "function": { "name": name } }
  }
}

///|
fn response_format_to_json(
  format : @provider.ResponseFormat,
  supports_structured_outputs : Bool,
  strict_override : Bool?,
) -> Json? {
  match format {
    @provider.Text => None
    @provider.JsonResponse(config) =>
      match config.schema {
        Some(schema) if supports_structured_outputs => {
          let json_schema : Map[String, Json] = Map([
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(strict_override.unwrap_or(true))),
          ])
          if config.description is Some(value) {
            json_schema["description"] = Json::string(value)
          }
          Some(
            (
              {
                "type": "json_schema",
                "json_schema": Json::object(json_schema),
              } : Json),
          )
        }
        _ => Some(({ "type": "json_object" } : Json))
      }
  }
}

///|
fn encode_chat_request_with_options(
  model_id : String,
  options : @provider.ChatCallOptions,
  messages : Array[Json],
  provider_options : OpenAICompatibleChatOptions,
  include_usage : Bool,
  stream : Bool,
  supports_structured_outputs : Bool,
  supports_top_k : Bool,
  supports_frequency_penalty : Bool,
) -> Json {
  let reasoning_effort = match provider_options.reasoning_effort {
    Some(value) => Some(value)
    None => openai_compatible_reasoning_effort(options.reasoning_effort)
  }
  let tools : Array[Json] = []
  for tool in options.tools {
    if tool_definition_to_json(tool) is Some(value) {
      tools.push(value)
    }
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("messages", Json::array(messages)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if stream && include_usage {
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
      ..if supports_top_k && options.top_k is Some(value) {
        [("top_k", Json::number(value))]
      },
      ..if supports_frequency_penalty &&
        options.frequency_penalty is Some(value) {
        [("frequency_penalty", Json::number(value))]
      },
      ..if options.presence_penalty is Some(value) {
        [("presence_penalty", Json::number(value))]
      },
      ..if options.seed is Some(value) {
        [("seed", Json::number(value.to_double()))]
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
      ..if provider_options.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if reasoning_effort is Some(value) {
        [("reasoning_effort", Json::string(value))]
      },
      ..if provider_options.text_verbosity is Some(value) {
        [("verbosity", Json::string(value))]
      },
    ],
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    match options.tool_choice {
      Some(choice) => fields["tool_choice"] = tool_choice_to_json(choice)
      None => ()
    }
  }
  if response_format_to_json(
      options.response_format,
      supports_structured_outputs,
      Some(provider_options.strict_json_schema.unwrap_or(true)),
    )
    is Some(format) {
    fields["response_format"] = format
  }
  for entry in provider_options.extensions.iter2() {
    let (key, value) = entry
    fields[chat_option_wire_key(key)] = value
  }
  Json::object(fields)
}

///|
/// Provider options are authored with the same camelCase names as the AI SDK
/// schemas. Normalize the common OpenAI-compatible fields, while preserving
/// unknown provider extensions verbatim.
fn chat_option_wire_key(key : String) -> String {
  match key {
    "parallelToolCalls" => "parallel_tool_calls"
    "logitBias" => "logit_bias"
    "maxTokens" => "max_tokens"
    "frequencyPenalty" => "frequency_penalty"
    "presencePenalty" => "presence_penalty"
    "stopSequences" => "stop"
    "toolChoice" => "tool_choice"
    other => other
  }
}

///|
/// Encode normalized options as an OpenAI-compatible Chat Completions request.
pub fn encode_chat_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = false,
  stream? : Bool = true,
  provider_name? : String = "",
  supports_structured_outputs? : Bool = false,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  prompt_converter? : OpenAICompatiblePromptConverter = default_openai_compatible_prompt_converter,
) -> Json raise {
  let parsed = parse_compatible_chat_options(options, provider_name)
  let conversion = prompt_converter(
    options.messages,
    preserve_reasoning,
    provider_name,
  )
  encode_chat_request_with_options(
    model_id,
    options,
    conversion.messages,
    parsed.options,
    include_usage,
    stream,
    supports_structured_outputs,
    supports_top_k,
    supports_frequency_penalty,
  )
}

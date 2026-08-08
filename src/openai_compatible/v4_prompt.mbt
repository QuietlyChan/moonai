///|
fn compatible_v4_thought_signature(options : Map[String, Json]) -> String? {
  match options.get("google") {
    Some(Object(values)) =>
      match values.get("thoughtSignature") {
        Some(String(value)) if value != "" => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn compatible_v4_file_base64(
  data : @provider.LanguageModelV4FileData,
) -> String raise {
  @provider_utils.convert_to_base64(data)
}

///|
fn compatible_v4_file_content(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
  filename : String?,
) -> Json raise {
  match data {
    @provider.V4FileReference(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="file parts with provider references",
      )
    @provider.V4FileText(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="text file parts",
      )
    _ => ()
  }
  let top_level = @provider_utils.get_top_level_media_type(media_type)
  if top_level == "image" {
    let url = match data {
      @provider.V4FileUrl(value) => value
      _ => {
        let encoded = compatible_v4_file_base64(data)
        let full_media_type = @provider_utils.resolve_full_media_type(
          media_type, encoded,
        )
        data_uri(full_media_type, encoded)
      }
    }
    { "type": "image_url", "image_url": { "url": url } }
  } else if top_level == "audio" {
    guard !(data is @provider.V4FileUrl(_)) else {
      raise @provider.UnsupportedFunctionalityError(
        functionality="audio file parts with URLs",
      )
    }
    let encoded = compatible_v4_file_base64(data)
    let full_media_type = @provider_utils.resolve_full_media_type(
      media_type, encoded,
    )
    let format = match full_media_type {
      "audio/wav" => "wav"
      "audio/mp3" | "audio/mpeg" => "mp3"
      _ =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="audio media type \{full_media_type}",
        )
    }
    {
      "type": "input_audio",
      "input_audio": { "data": encoded, "format": format },
    }
  } else if top_level == "application" {
    guard !(data is @provider.V4FileUrl(_)) else {
      raise @provider.UnsupportedFunctionalityError(
        functionality="PDF file parts with URLs",
      )
    }
    let encoded = compatible_v4_file_base64(data)
    let full_media_type = @provider_utils.resolve_full_media_type(
      media_type, encoded,
    )
    guard full_media_type == "application/pdf" else {
      raise @provider.UnsupportedFunctionalityError(
        functionality="file part media type \{full_media_type}",
      )
    }
    {
      "type": "file",
      "file": {
        "filename": filename.unwrap_or("document.pdf"),
        "file_data": data_uri(full_media_type, encoded),
      },
    }
  } else if top_level == "text" {
    let text = match data {
      @provider.V4FileUrl(value) => value
      @provider.V4FileData(value) => @provider_utils.decode_base64_text(value)
      @provider.V4FileBytes(value) => @utf8.decode_lossy(value)
      @provider.V4FileReference(_) | @provider.V4FileText(_) =>
        fail("unsupported text file data")
    }
    { "type": "text", "text": text }
  } else {
    raise @provider.UnsupportedFunctionalityError(
      functionality="file part media type \{media_type}",
    )
  }
}

///|
fn compatible_v4_user_content_part(
  part : @provider.LanguageModelV4PromptPart,
) -> Json raise {
  let content = match part {
    @provider.V4PromptText(text~, ..) =>
      ({ "type": "text", "text": text } : Json)
    @provider.V4PromptFile(data~, media_type~, filename~, ..) =>
      compatible_v4_file_content(data, media_type, filename)
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="non-text/file parts in OpenAI-compatible user messages",
      )
  }
  let options = match part {
    @provider.V4PromptText(provider_options~, ..)
    | @provider.V4PromptReasoning(provider_options~, ..)
    | @provider.V4PromptReasoningFile(provider_options~, ..)
    | @provider.V4PromptCustom(provider_options~, ..)
    | @provider.V4PromptFile(provider_options~, ..) => provider_options
    @provider.V4PromptToolCall(value) => value.provider_options
    @provider.V4PromptToolResult(value) => value.provider_options
    @provider.V4PromptToolApprovalResponse(value) => value.provider_options
  }
  with_openai_compatible_wire_metadata(content, options)
}

///|
fn compatible_v4_tool_call_to_json(
  call : @provider.LanguageModelV4ToolCallPart,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("id", Json::string(call.tool_call_id)),
    ("type", Json::string("function")),
    (
      "function",
      ({ "name": call.tool_name, "arguments": call.input.stringify() } : Json),
    ),
  ])
  for entry in openai_compatible_wire_metadata(call.provider_options).iter2() {
    fields[entry.0] = entry.1
  }
  if compatible_v4_thought_signature(call.provider_options) is Some(value) {
    fields["extra_content"] = { "google": { "thought_signature": value } }
  }
  Json::object(fields)
}

///|
fn compatible_v4_file_data_json(
  data : @provider.LanguageModelV4FileData,
) -> Json {
  match data {
    @provider.V4FileData(value) => { "type": "data", "data": value }
    @provider.V4FileBytes(value) =>
      { "type": "data", "data": @provider_utils.convert_bytes_to_base64(value) }
    @provider.V4FileUrl(value) => { "type": "url", "url": value }
    @provider.V4FileReference(value) => {
      let reference : Map[String, Json] = Map([])
      for provider in value.providers() {
        if value.get(provider) is Some(id) {
          reference[provider] = Json::string(id)
        }
      }
      { "type": "reference", "reference": Json::object(reference) }
    }
    @provider.V4FileText(value) => { "type": "text", "text": value }
  }
}

///|
fn compatible_v4_tool_result_content_json(
  part : @provider.LanguageModelV4ToolResultContentPart,
) -> Json {
  let fields : Map[String, Json] = match part {
    @provider.V4ToolResultTextContent(text~, provider_options~) =>
      Map(
        [
          ("type", Json::string("text")),
          ("text", Json::string(text)),
          ..if provider_options.length() > 0 {
            [("providerOptions", Json::object(provider_options))]
          },
        ],
      )
    @provider.V4ToolResultFileContent(
      data~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      Map(
        [
          ("type", Json::string("file")),
          ("data", compatible_v4_file_data_json(data)),
          ("mediaType", Json::string(media_type)),
          ..if filename is Some(value) {
            [("filename", Json::string(value))]
          },
          ..if provider_options.length() > 0 {
            [("providerOptions", Json::object(provider_options))]
          },
        ],
      )
    @provider.V4ToolResultCustomContent(provider_options~) =>
      Map(
        [
          ("type", Json::string("custom")),
          ..if provider_options.length() > 0 {
            [("providerOptions", Json::object(provider_options))]
          },
        ],
      )
  }
  Json::object(fields)
}

///|
fn compatible_v4_tool_result_text(
  output : @provider.LanguageModelV4ToolResultOutput,
) -> String {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..)
    | @provider.V4ToolResultErrorText(value~, ..) => value
    @provider.V4ToolResultExecutionDenied(reason~, ..) =>
      reason.unwrap_or("Tool call execution denied.")
    @provider.V4ToolResultJsonOutput(value~, ..)
    | @provider.V4ToolResultErrorJson(value~, ..) => value.stringify()
    @provider.V4ToolResultContentOutput(value~, ..) =>
      Json::array(
        [
          for part in value => compatible_v4_tool_result_content_json(part)
        ],
      ).stringify()
  }
}

///|
fn compatible_v4_system_message(
  content : String,
  provider_options : Map[String, Json],
) -> Json {
  with_openai_compatible_wire_metadata(
    { "role": "system", "content": content },
    provider_options,
  )
}

///|
fn compatible_v4_user_message(
  content : Array[@provider.LanguageModelV4PromptPart],
  provider_options : Map[String, Json],
) -> Json raise {
  if content.length() == 1 {
    match content[0] {
      @provider.V4PromptText(text~, provider_options=part_options) =>
        return with_openai_compatible_wire_metadata(
          { "role": "user", "content": text },
          part_options,
        )
      _ => ()
    }
  }
  with_openai_compatible_wire_metadata(
    {
      "role": "user",
      "content": Json::array(
        [
          for part in content => compatible_v4_user_content_part(part)
        ],
      ),
    },
    provider_options,
  )
}

///|
fn compatible_v4_assistant_message(
  content : Array[@provider.LanguageModelV4PromptPart],
  provider_options : Map[String, Json],
) -> Json {
  let text_builder = StringBuilder::new()
  let reasoning_builder = StringBuilder::new()
  let tool_calls : Array[Json] = []
  for part in content {
    match part {
      @provider.V4PromptText(text~, ..) => text_builder.write_string(text)
      @provider.V4PromptReasoning(text~, ..) =>
        reasoning_builder.write_string(text)
      @provider.V4PromptToolCall(value) =>
        tool_calls.push(compatible_v4_tool_call_to_json(value))
      _ => ()
    }
  }
  let text_value = text_builder.to_string()
  let reasoning_value = reasoning_builder.to_string()
  with_openai_compatible_wire_metadata(
    Json::object(
      Map(
        [
          ("role", Json::string("assistant")),
          (
            "content",
            if tool_calls.length() > 0 && text_value == "" {
              Json::null()
            } else {
              Json::string(text_value)
            },
          ),
          ..if reasoning_value != "" {
            [("reasoning_content", Json::string(reasoning_value))]
          },
          ..if tool_calls.length() > 0 {
            [("tool_calls", Json::array(tool_calls))]
          },
        ],
      ),
    ),
    provider_options,
  )
}

///|
fn compatible_v4_tool_messages(
  content : Array[@provider.LanguageModelV4PromptPart],
) -> Array[Json] {
  let result : Array[Json] = []
  for part in content {
    match part {
      @provider.V4PromptToolResult(value) =>
        result.push(
          with_openai_compatible_wire_metadata(
            {
              "role": "tool",
              "tool_call_id": value.tool_call_id,
              "content": compatible_v4_tool_result_text(value.output),
            },
            value.provider_options,
          ),
        )
      @provider.V4PromptToolApprovalResponse(_) => ()
      _ => ()
    }
  }
  result
}

///|
/// Convert a V4 prompt using AI SDK's OpenAI-compatible Chat Completions
/// message semantics.
pub fn default_openai_compatible_v4_prompt_converter(
  prompt : @provider.LanguageModelV4Prompt,
  _provider_name : String,
) -> OpenAICompatiblePromptConversion raise {
  let messages : Array[Json] = []
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, provider_options~) =>
        messages.push(compatible_v4_system_message(content, provider_options))
      @provider.V4UserMessage(content~, provider_options~) =>
        messages.push(compatible_v4_user_message(content, provider_options))
      @provider.V4AssistantMessage(content~, provider_options~) =>
        messages.push(
          compatible_v4_assistant_message(content, provider_options),
        )
      @provider.V4ToolMessage(content~, ..) =>
        for converted in compatible_v4_tool_messages(content) {
          messages.push(converted)
        }
    }
  }
  { messages, warnings: [] }
}

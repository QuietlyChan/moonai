///|
priv struct OpenAIChatV4PromptConversion {
  messages : Array[Json]
  warnings : Array[@provider.Warning]
}

///|
fn openai_v4_prompt_part_options(
  part : @provider.LanguageModelV4PromptPart,
) -> Map[String, Json] {
  match part {
    @provider.V4PromptText(provider_options~, ..)
    | @provider.V4PromptReasoning(provider_options~, ..)
    | @provider.V4PromptReasoningFile(provider_options~, ..)
    | @provider.V4PromptCustom(provider_options~, ..)
    | @provider.V4PromptFile(provider_options~, ..) => provider_options
    @provider.V4PromptToolCall(value) => value.provider_options
    @provider.V4PromptToolResult(value) => value.provider_options
    @provider.V4PromptToolApprovalResponse(value) => value.provider_options
  }
}

///|
fn openai_v4_inline_file_data(
  data : @provider.LanguageModelV4FileData,
) -> String raise {
  @provider_utils.convert_to_base64(data)
}

///|
fn openai_v4_chat_file_part(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
  filename : String?,
  provider_options : Map[String, Json],
  index : Int,
) -> Json raise {
  let content : Json = match data {
    @provider.V4FileReference(reference) =>
      {
        "type": "file",
        "file": {
          "file_id": @provider_utils.resolve_provider_reference(
            reference, "openai",
          ),
        },
      }
    @provider.V4FileText(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="text file parts",
      )
    _ => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      if top_level == "image" {
        let url = match data {
          @provider.V4FileUrl(value) => value
          _ => {
            let encoded = openai_v4_inline_file_data(data)
            openai_data_uri(
              @provider_utils.resolve_full_media_type(media_type, encoded),
              encoded,
            )
          }
        }
        {
          "type": "image_url",
          "image_url": openai_image_url_value(url, provider_options),
        }
      } else if top_level == "audio" {
        guard !(data is @provider.V4FileUrl(_)) else {
          raise @provider.UnsupportedFunctionalityError(
            functionality="audio file parts with URLs",
          )
        }
        let encoded = openai_v4_inline_file_data(data)
        let full_media_type = @provider_utils.resolve_full_media_type(
          media_type, encoded,
        )
        let format = match full_media_type {
          "audio/wav" => "wav"
          "audio/mp3" | "audio/mpeg" => "mp3"
          _ =>
            raise @provider.UnsupportedFunctionalityError(
              functionality="audio content parts with media type \{full_media_type}",
            )
        }
        {
          "type": "input_audio",
          "input_audio": { "data": encoded, "format": format },
        }
      } else {
        guard !(data is @provider.V4FileUrl(_)) else {
          raise @provider.UnsupportedFunctionalityError(
            functionality="PDF file parts with URLs",
          )
        }
        let encoded = openai_v4_inline_file_data(data)
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
            "filename": filename.unwrap_or("part-\{index}.pdf"),
            "file_data": openai_data_uri(full_media_type, encoded),
          },
        }
      }
    }
  }
  with_openai_prompt_cache_breakpoint(content, provider_options)
}

///|
fn openai_v4_chat_user_part(
  part : @provider.LanguageModelV4PromptPart,
  index : Int,
) -> Json raise {
  let options = openai_v4_prompt_part_options(part)
  match part {
    @provider.V4PromptText(text~, ..) =>
      openai_text_content_with_breakpoint(text, options)
    @provider.V4PromptFile(data~, media_type~, filename~, ..) =>
      openai_v4_chat_file_part(data, media_type, filename, options, index)
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="non-text/file parts in OpenAI Chat user messages",
      )
  }
}

///|
fn openai_v4_chat_tool_call(
  call : @provider.LanguageModelV4ToolCallPart,
) -> Json {
  {
    "id": call.tool_call_id,
    "type": "function",
    "function": { "name": call.tool_name, "arguments": call.input.stringify() },
  }
}

///|
fn openai_v4_tool_content_json(
  part : @provider.LanguageModelV4ToolResultContentPart,
) -> Json {
  match part {
    @provider.V4ToolResultTextContent(text~, ..) =>
      { "type": "text", "text": text }
    @provider.V4ToolResultFileContent(data~, media_type~, filename~, ..) => {
      let data_json : Json = match data {
        @provider.V4FileData(value) => { "type": "data", "data": value }
        @provider.V4FileBytes(value) =>
          {
            "type": "data",
            "data": @provider_utils.convert_bytes_to_base64(value),
          }
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
      Json::object(
        Map(
          [
            ("type", Json::string("file")),
            ("data", data_json),
            ("mediaType", Json::string(media_type)),
            ..if filename is Some(value) {
              [("filename", Json::string(value))]
            },
          ],
        ),
      )
    }
    @provider.V4ToolResultCustomContent(..) => { "type": "custom" }
  }
}

///|
fn openai_v4_chat_tool_result_text(
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
      Json::array([ for part in value => openai_v4_tool_content_json(part) ]).stringify()
  }
}

///|
fn openai_v4_tool_output_options(
  output : @provider.LanguageModelV4ToolResultOutput,
) -> Map[String, Json] {
  match output {
    @provider.V4ToolResultTextOutput(provider_options~, ..)
    | @provider.V4ToolResultJsonOutput(provider_options~, ..)
    | @provider.V4ToolResultExecutionDenied(provider_options~, ..)
    | @provider.V4ToolResultErrorText(provider_options~, ..)
    | @provider.V4ToolResultErrorJson(provider_options~, ..)
    | @provider.V4ToolResultContentOutput(provider_options~, ..) =>
      provider_options
  }
}

///|
fn openai_v4_tool_result_breakpoint(
  result : @provider.LanguageModelV4ToolResultPart,
) -> Json? {
  match result.output {
    @provider.V4ToolResultContentOutput(value~, ..) => {
      for part in value {
        let options = match part {
          @provider.V4ToolResultTextContent(provider_options~, ..)
          | @provider.V4ToolResultFileContent(provider_options~, ..)
          | @provider.V4ToolResultCustomContent(provider_options~) =>
            provider_options
        }
        if openai_prompt_cache_breakpoint(options) is Some(value) {
          return Some(value)
        }
      }
      openai_prompt_cache_breakpoint(result.provider_options)
    }
    output =>
      match
        openai_prompt_cache_breakpoint(openai_v4_tool_output_options(output)) {
        Some(value) => Some(value)
        None => openai_prompt_cache_breakpoint(result.provider_options)
      }
  }
}

///|
fn openai_v4_chat_tool_message(
  result : @provider.LanguageModelV4ToolResultPart,
) -> Json {
  let value = openai_v4_chat_tool_result_text(result.output)
  let content = match openai_v4_tool_result_breakpoint(result) {
    Some(breakpoint) =>
      Json::array([
        { "type": "text", "text": value, "prompt_cache_breakpoint": breakpoint },
      ])
    None => Json::string(value)
  }
  { "role": "tool", "tool_call_id": result.tool_call_id, "content": content }
}

///|
fn openai_v4_chat_system_message(
  content : String,
  provider_options : Map[String, Json],
  system_message_mode : String,
  warnings : Array[@provider.Warning],
) -> Json? {
  if system_message_mode == "remove" {
    warnings.push(
      @provider.Warning::Other(
        message="system messages are removed for this model",
      ),
    )
    return None
  }
  let value = match openai_prompt_cache_breakpoint(provider_options) {
    Some(_) =>
      Json::array([
        openai_text_content_with_breakpoint(content, provider_options),
      ])
    None => Json::string(content)
  }
  Some({ "role": system_message_mode, "content": value })
}

///|
fn openai_v4_chat_user_message(
  content : Array[@provider.LanguageModelV4PromptPart],
) -> Json raise {
  if content.length() == 1 {
    match content[0] {
      @provider.V4PromptText(text~, provider_options~) if openai_prompt_cache_breakpoint(
          provider_options,
        )
        is None => return { "role": "user", "content": text }
      _ => ()
    }
  }
  {
    "role": "user",
    "content": Json::array(
      [
        for index, part in content => openai_v4_chat_user_part(part, index)
      ],
    ),
  }
}

///|
fn openai_v4_chat_assistant_message(
  content : Array[@provider.LanguageModelV4PromptPart],
) -> Json {
  let text_builder = StringBuilder::new()
  let text_parts : Array[Json] = []
  let tool_calls : Array[Json] = []
  let mut has_breakpoint = false
  for part in content {
    match part {
      @provider.V4PromptText(text~, provider_options~) => {
        text_builder.write_string(text)
        if openai_prompt_cache_breakpoint(provider_options) is Some(_) {
          has_breakpoint = true
        }
        text_parts.push(
          openai_text_content_with_breakpoint(text, provider_options),
        )
      }
      @provider.V4PromptToolCall(value) =>
        tool_calls.push(openai_v4_chat_tool_call(value))
      _ => ()
    }
  }
  let text = text_builder.to_string()
  let fields : Map[String, Json] = Map([
    ("role", Json::string("assistant")),
    (
      "content",
      if has_breakpoint {
        Json::array(text_parts)
      } else if tool_calls.length() > 0 && text == "" {
        Json::null()
      } else {
        Json::string(text)
      },
    ),
  ])
  if tool_calls.length() > 0 {
    fields["tool_calls"] = Json::array(tool_calls)
  }
  Json::object(fields)
}

///|
fn convert_v4_prompt_to_openai_chat(
  prompt : @provider.LanguageModelV4Prompt,
  system_message_mode : String,
) -> OpenAIChatV4PromptConversion raise {
  let messages : Array[Json] = []
  let warnings : Array[@provider.Warning] = []
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, provider_options~) =>
        match
          openai_v4_chat_system_message(
            content, provider_options, system_message_mode, warnings,
          ) {
          Some(value) => messages.push(value)
          None => ()
        }
      @provider.V4UserMessage(content~, ..) =>
        messages.push(openai_v4_chat_user_message(content))
      @provider.V4AssistantMessage(content~, ..) =>
        messages.push(openai_v4_chat_assistant_message(content))
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(value) =>
              messages.push(openai_v4_chat_tool_message(value))
            @provider.V4PromptToolApprovalResponse(_) => ()
            _ => ()
          }
        }
    }
  }
  { messages, warnings }
}

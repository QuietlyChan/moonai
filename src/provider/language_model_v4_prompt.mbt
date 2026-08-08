///|
/// One role-specific V4 prompt message.
pub(all) enum LanguageModelV4Message {
  V4SystemMessage(content~ : String, provider_options~ : Map[String, Json])
  V4UserMessage(
    content~ : Array[LanguageModelV4PromptPart],
    provider_options~ : Map[String, Json]
  )
  V4AssistantMessage(
    content~ : Array[LanguageModelV4PromptPart],
    provider_options~ : Map[String, Json]
  )
  V4ToolMessage(
    content~ : Array[LanguageModelV4PromptPart],
    provider_options~ : Map[String, Json]
  )
} derive(Debug, Eq)

///|
/// Prompt shape passed to a V4 language model.
///
/// The wrapper keeps the ordered message array in a named struct because
/// MoonBit does not allow methods on type aliases.
pub(all) struct LanguageModelV4Prompt {
  messages : Array[LanguageModelV4Message]
} derive(Debug, Eq)

///|
/// Construct a V4 prompt from ordered messages.
pub fn LanguageModelV4Prompt::new(
  messages : Array[LanguageModelV4Message],
) -> LanguageModelV4Prompt {
  { messages, }
}

///|
fn copy_prompt_options(options : Map[String, Json]) -> Map[String, Json] {
  copy_provider_metadata(options)
}

///|
/// Convert one normalized provider prompt part to the V4 shape.
fn LanguageModelV4PromptPart::from_content_part(
  part : LanguageModelContentPart,
) -> LanguageModelV4PromptPart? {
  let options = copy_prompt_options(part.provider_options())
  match part.without_provider_options() {
    Text(value) => Some(V4PromptText(text=value, provider_options=options))
    ImageUrl(value) =>
      Some(
        V4PromptFile(
          data=V4FileUrl(value),
          media_type="image/*",
          filename=None,
          provider_options=options,
        ),
      )
    ImageData(data~, media_type~) =>
      Some(
        V4PromptFile(
          data=V4FileData(data),
          media_type~,
          filename=None,
          provider_options=options,
        ),
      )
    AudioData(data~, format~) =>
      Some(
        V4PromptFile(
          data=V4FileData(data),
          media_type=format,
          filename=None,
          provider_options=options,
        ),
      )
    FileUrl(url~, media_type~, filename~) =>
      Some(
        V4PromptFile(
          data=V4FileUrl(url),
          media_type~,
          filename=if filename == "" { None } else { Some(filename) },
          provider_options=options,
        ),
      )
    FileData(data~, media_type~, filename~) =>
      Some(
        V4PromptFile(
          data=V4FileData(data),
          media_type~,
          filename=if filename == "" { None } else { Some(filename) },
          provider_options=options,
        ),
      )
    FileReference(reference~, media_type~, filename~) =>
      Some(
        V4PromptFile(
          data=V4FileReference(reference),
          media_type~,
          filename=if filename == "" { None } else { Some(filename) },
          provider_options=options,
        ),
      )
    Reasoning(value) =>
      Some(V4PromptReasoning(text=value, provider_options=options))
    ReasoningFileUrl(url~, media_type~) =>
      Some(
        V4PromptReasoningFile(
          data=V4FileUrl(url),
          media_type~,
          provider_options=options,
        ),
      )
    ReasoningFileData(data~, media_type~) =>
      Some(
        V4PromptReasoningFile(
          data=V4FileData(data),
          media_type~,
          provider_options=options,
        ),
      )
    Custom(kind~) => Some(V4PromptCustom(kind~, provider_options=options))
    ToolCallPart(value) =>
      Some(V4PromptToolCall(LanguageModelV4ToolCallPart::from_tool_call(value)))
    ToolResultPart(value) =>
      Some(
        V4PromptToolResult(LanguageModelV4ToolResultPart::from_legacy(value)),
      )
    // Approval requests are an AI-layer coordination detail. AI SDK removes
    // them before constructing a provider-facing V4 prompt.
    ToolApprovalRequestPart(_) => None
    ToolApprovalResponsePart(value) if value.provider_executed =>
      Some(
        V4PromptToolApprovalResponse(
          LanguageModelV4ToolApprovalResponsePart::from_legacy(value),
        ),
      )
    ToolApprovalResponsePart(_) => None
    ProviderOptions(part~, ..) =>
      LanguageModelV4PromptPart::from_content_part(part)
  }
}

///|
/// Convert one V4 file to the normalized prompt representation.
fn LanguageModelV4FileData::to_content_part(
  self : LanguageModelV4FileData,
  media_type : String,
  filename : String,
) -> LanguageModelContentPart {
  match self {
    V4FileData(data) if media_type.has_prefix("image/") =>
      LanguageModelContentPart::image_data(data~, media_type~)
    V4FileBytes(data) if media_type.has_prefix("image/") =>
      LanguageModelContentPart::image_data(
        data=@base64.encode(data),
        media_type~,
      )
    V4FileUrl(url) if media_type == "image/*" =>
      LanguageModelContentPart::image_url(url)
    V4FileData(data) =>
      LanguageModelContentPart::file_data(data~, media_type~, filename~)
    V4FileBytes(data) =>
      LanguageModelContentPart::file_data(
        data=@base64.encode(data),
        media_type~,
        filename~,
      )
    V4FileUrl(url) =>
      LanguageModelContentPart::file_url(url~, media_type~, filename~)
    V4FileReference(reference) =>
      LanguageModelContentPart::file_reference(
        reference~,
        media_type~,
        filename~,
      )
    V4FileText(text) => LanguageModelContentPart::text(text)
  }
}

///|
/// Convert one V4 prompt part to the normalized provider representation.
fn LanguageModelV4PromptPart::to_content_part(
  self : LanguageModelV4PromptPart,
) -> LanguageModelContentPart {
  match self {
    V4PromptText(text~, provider_options~) =>
      LanguageModelContentPart::text(text).with_provider_options(
        provider_options,
      )
    V4PromptReasoning(text~, provider_options~) =>
      LanguageModelContentPart::reasoning(text).with_provider_options(
        provider_options,
      )
    V4PromptReasoningFile(data~, media_type~, provider_options~) =>
      match data {
        V4FileData(value) =>
          LanguageModelContentPart::reasoning_file_data(data=value, media_type~).with_provider_options(
            provider_options,
          )
        V4FileBytes(value) =>
          LanguageModelContentPart::reasoning_file_data(
            data=@base64.encode(value),
            media_type~,
          ).with_provider_options(provider_options)
        V4FileUrl(value) =>
          LanguageModelContentPart::reasoning_file_url(url=value, media_type~).with_provider_options(
            provider_options,
          )
        V4FileReference(_) =>
          LanguageModelContentPart::custom("provider.reasoning-file-reference").with_provider_options(
            provider_options,
          )
        V4FileText(value) =>
          LanguageModelContentPart::reasoning(value).with_provider_options(
            provider_options,
          )
      }
    V4PromptCustom(kind~, provider_options~) =>
      LanguageModelContentPart::custom(kind).with_provider_options(
        provider_options,
      )
    V4PromptFile(data~, media_type~, filename~, provider_options~) =>
      data
      .to_content_part(media_type, filename.unwrap_or(""))
      .with_provider_options(provider_options)
    V4PromptToolCall(value) =>
      LanguageModelContentPart::tool_call(value.to_tool_call())
    V4PromptToolResult(value) =>
      LanguageModelContentPart::tool_result(value.to_legacy())
    V4PromptToolApprovalResponse(value) =>
      LanguageModelContentPart::tool_approval_response(value.to_legacy())
  }
}

///|
fn prompt_parts_from_message(
  message : LanguageModelMessage,
) -> Array[LanguageModelV4PromptPart] {
  let parts : Array[LanguageModelV4PromptPart] = []
  match message.reasoning_content {
    Some(value) =>
      parts.push(
        V4PromptReasoning(
          text=value,
          provider_options=copy_prompt_options(message.provider_options),
        ),
      )
    None => ()
  }
  if message.content != "" {
    parts.push(V4PromptText(text=message.content, provider_options=Map([])))
  }
  for part in message.parts {
    match LanguageModelV4PromptPart::from_content_part(part) {
      Some(value) => parts.push(value)
      None => ()
    }
  }
  for call in message.tool_calls {
    let mut present = false
    for part in message.parts {
      match part.without_provider_options() {
        ToolCallPart(existing) if existing.id == call.id && call.id != "" =>
          present = true
        _ => ()
      }
    }
    if !present {
      parts.push(
        V4PromptToolCall(LanguageModelV4ToolCallPart::from_tool_call(call)),
      )
    }
  }
  parts
}

///|
fn tool_prompt_parts_from_message(
  message : LanguageModelMessage,
  tool_call_id : String,
) -> Array[LanguageModelV4PromptPart] {
  let parts : Array[LanguageModelV4PromptPart] = []
  let wire_output_parts : Array[LanguageModelV4ToolResultContentPart] = []
  let mut filtered_approval_response = false
  for part in message.parts {
    match part.without_provider_options() {
      ToolResultPart(value) =>
        parts.push(
          V4PromptToolResult(LanguageModelV4ToolResultPart::from_legacy(value)),
        )
      ToolApprovalResponsePart(value) if value.provider_executed =>
        parts.push(
          V4PromptToolApprovalResponse(
            LanguageModelV4ToolApprovalResponsePart::from_legacy(value),
          ),
        )
      ToolApprovalResponsePart(_) => filtered_approval_response = true
      Text(text) =>
        wire_output_parts.push(
          V4ToolResultTextContent(
            text~,
            provider_options=part.provider_options(),
          ),
        )
      ImageUrl(url) =>
        wire_output_parts.push(
          V4ToolResultFileContent(
            data=V4FileUrl(url),
            media_type="image/*",
            filename=None,
            provider_options=part.provider_options(),
          ),
        )
      ImageData(data~, media_type~) =>
        wire_output_parts.push(
          V4ToolResultFileContent(
            data=V4FileData(data),
            media_type~,
            filename=None,
            provider_options=part.provider_options(),
          ),
        )
      AudioData(data~, format~) =>
        wire_output_parts.push(
          V4ToolResultFileContent(
            data=V4FileData(data),
            media_type=format,
            filename=None,
            provider_options=part.provider_options(),
          ),
        )
      FileUrl(url~, media_type~, filename~) =>
        wire_output_parts.push(
          V4ToolResultFileContent(
            data=V4FileUrl(url),
            media_type~,
            filename=if filename == "" { None } else { Some(filename) },
            provider_options=part.provider_options(),
          ),
        )
      FileData(data~, media_type~, filename~) =>
        wire_output_parts.push(
          V4ToolResultFileContent(
            data=V4FileData(data),
            media_type~,
            filename=if filename == "" { None } else { Some(filename) },
            provider_options=part.provider_options(),
          ),
        )
      FileReference(reference~, media_type~, filename~) =>
        wire_output_parts.push(
          V4ToolResultFileContent(
            data=V4FileReference(reference),
            media_type~,
            filename=if filename == "" { None } else { Some(filename) },
            provider_options=part.provider_options(),
          ),
        )
      Custom(kind=provider_kind) =>
        wire_output_parts.push(
          V4ToolResultCustomContent(
            provider_options=Map([("kind", Json::string(provider_kind))]),
          ),
        )
      ProviderOptions(_, ..) => ()
      _ => ()
    }
  }
  if wire_output_parts.length() > 0 {
    parts.push(
      V4PromptToolResult(
        LanguageModelV4ToolResultPart::content(
          tool_call_id~,
          tool_name="",
          value=wire_output_parts,
        ),
      ),
    )
  }
  if parts.length() == 0 && !filtered_approval_response {
    parts.push(
      V4PromptToolResult(
        LanguageModelV4ToolResultPart::text(
          tool_call_id~,
          tool_name="",
          value=message.content,
          provider_options=copy_prompt_options(message.provider_options),
        ),
      ),
    )
  }
  parts
}

///|
/// Collapse the single text part used by a V4 user or assistant message back
/// into the wire message `content` field. Keeping this distinction matters
/// for an explicit `ChatModel` adapter, whose implementations can
/// distinguish text messages from multimodal messages.
fn wire_text_content(parts : Array[LanguageModelV4PromptPart]) -> String? {
  if parts.length() == 1 {
    match parts[0] {
      V4PromptText(text~, ..) => Some(text)
      _ => None
    }
  } else {
    None
  }
}

///|
/// Convert the normalized prompt used by wire adapters to V4.
pub fn LanguageModelV4Prompt::from_language_model_prompt(
  prompt : LanguageModelPrompt,
) -> LanguageModelV4Prompt {
  let result = LanguageModelV4Prompt::new([])
  for message in prompt {
    let options = copy_prompt_options(message.provider_options)
    match message.role {
      System =>
        result.messages.push(
          V4SystemMessage(content=message.content, provider_options=options),
        )
      User =>
        result.messages.push(
          V4UserMessage(
            content=prompt_parts_from_message(message),
            provider_options=options,
          ),
        )
      Assistant =>
        result.messages.push(
          V4AssistantMessage(
            content=prompt_parts_from_message(message),
            provider_options=options,
          ),
        )
      Tool(tool_call_id) => {
        let content = tool_prompt_parts_from_message(message, tool_call_id)
        if content.length() > 0 {
          result.messages.push(
            V4ToolMessage(content~, provider_options=options),
          )
        }
      }
    }
  }
  result
}

///|
fn tool_call_id_from_v4_parts(
  parts : Array[LanguageModelV4PromptPart],
) -> String {
  for part in parts {
    match part {
      V4PromptToolResult(value) => return value.tool_call_id
      _ => ()
    }
  }
  ""
}

///|
/// Convert the V4 prompt to the normalized representation consumed by the
/// current provider wire implementations.
pub fn LanguageModelV4Prompt::to_language_model_prompt(
  self : LanguageModelV4Prompt,
) -> LanguageModelPrompt {
  let result : LanguageModelPrompt = []
  for message in self.messages {
    match message {
      V4SystemMessage(content~, provider_options~) =>
        result.push(LanguageModelMessage::system(content, provider_options~))
      V4UserMessage(content~, provider_options~) =>
        match wire_text_content(content) {
          Some(text) =>
            match content[0] {
              V4PromptText(provider_options=part_options, ..) if part_options.length() >
                0 =>
                result.push(
                  LanguageModelMessage::user_parts(
                    [content[0].to_content_part()],
                    provider_options~,
                  ),
                )
              _ =>
                result.push(LanguageModelMessage::user(text, provider_options~))
            }
          None =>
            result.push(
              LanguageModelMessage::new(
                User,
                content="",
                parts=[ for part in content => part.to_content_part() ],
                provider_options~,
              ),
            )
        }
      V4AssistantMessage(content~, provider_options~) =>
        match wire_text_content(content) {
          Some(text) =>
            match content[0] {
              V4PromptText(provider_options=part_options, ..) if part_options.length() >
                0 =>
                result.push(
                  LanguageModelMessage::assistant_parts(
                    [content[0].to_content_part()],
                    provider_options~,
                  ),
                )
              _ =>
                result.push(
                  LanguageModelMessage::assistant(text, provider_options~),
                )
            }
          None =>
            result.push(
              LanguageModelMessage::new(
                Assistant,
                content="",
                parts=[ for part in content => part.to_content_part() ],
                provider_options~,
              ),
            )
        }
      V4ToolMessage(content~, provider_options~) =>
        result.push(
          LanguageModelMessage::new(
            Tool(tool_call_id_from_v4_parts(content)),
            content="",
            parts=[ for part in content => part.to_content_part() ],
            provider_options~,
          ),
        )
    }
  }
  result
}

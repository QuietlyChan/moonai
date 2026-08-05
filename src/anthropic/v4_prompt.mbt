///|
/// Anthropic wire prompt produced directly from the provider-neutral V4
/// prompt. Request shaping consumes this value without passing through the
/// pre-V4 LanguageModelMessage representation.
priv struct AnthropicV4PromptConversion {
  system : Array[Json]
  messages : Array[AnthropicWireMessage]
  beta_features : Array[String]
  warnings : Array[@provider.Warning]
}

///|
fn anthropic_v4_prompt_part_options(
  part : @provider.LanguageModelV4PromptPart,
) -> Map[String, Json] {
  match part {
    @provider.V4PromptText(provider_options~, ..)
    | @provider.V4PromptReasoning(provider_options~, ..)
    | @provider.V4PromptReasoningFile(provider_options~, ..)
    | @provider.V4PromptCustom(provider_options~, ..)
    | @provider.V4PromptFile(provider_options~, ..) => provider_options
    @provider.V4PromptToolCall(call) => call.provider_metadata
    @provider.V4PromptToolResult(result) => result.provider_options
    @provider.V4PromptToolApprovalRequest(_) => Map([])
    @provider.V4PromptToolApprovalResponse(response) =>
      response.provider_options
  }
}

///|
fn anthropic_v4_redacted_reasoning_data(
  options : Map[String, Json],
  provider_name : String,
) -> String? {
  let values = resolve_anthropic_prompt_options(options, provider_name)
  for field in ["redactedData", "redacted_data"] {
    match values.get(field) {
      Some(String(value)) if value != "" => return Some(value)
      _ => ()
    }
  }
  None
}

///|
fn anthropic_v4_text_kind(
  options : Map[String, Json],
  provider_name : String,
) -> String {
  let values = resolve_anthropic_prompt_options(options, provider_name)
  match anthropic_prompt_option(values, "type", "type") {
    Some(String(value)) => value
    _ => "text"
  }
}

///|
fn anthropic_v4_cacheable_content(content : Json) -> Bool {
  match content {
    { "type": String(kind), .. } =>
      kind != "thinking" &&
      kind != "redacted_thinking" &&
      kind != "container_upload"
    _ => true
  }
}

///|
fn with_anthropic_v4_message_cache_control(
  content : Json,
  part_options : Map[String, Json],
  message_options : Map[String, Json],
  is_last_part : Bool,
  provider_name : String,
) -> Json {
  if anthropic_v4_cacheable_content(content) {
    with_message_cache_control(
      content, part_options, message_options, is_last_part, provider_name,
    )
  } else {
    content
  }
}

///|
fn anthropic_v4_file_content(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
  filename : String?,
  provider_options : Map[String, Json],
  provider_name : String,
  beta_features : Array[String],
) -> Json raise {
  let scoped_options = resolve_anthropic_prompt_options(
    provider_options, provider_name,
  )
  let resolved_filename = filename.unwrap_or("")
  match data {
    @provider.V4FileReference(reference) => {
      let file_id = resolve_anthropic_file_reference(reference, provider_name)
      append_unique_beta(beta_features, "files-api-2025-04-14")
      if anthropic_container_upload(scoped_options) {
        { "type": "container_upload", "file_id": file_id }
      } else if @provider_utils.get_top_level_media_type(media_type) == "image" {
        { "type": "image", "source": { "type": "file", "file_id": file_id } }
      } else if media_type == "application/pdf" || media_type == "text/plain" {
        if media_type == "application/pdf" {
          append_unique_beta(beta_features, "pdfs-2024-09-25")
        }
        anthropic_document(
          { "type": "file", "file_id": file_id },
          resolved_filename,
          scoped_options,
        )
      } else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="Anthropic file media type: \{media_type}",
        )
      }
    }
    @provider.V4FileText(text) =>
      anthropic_document(
        { "type": "text", "media_type": "text/plain", "data": text },
        resolved_filename,
        scoped_options,
      )
    @provider.V4FileUrl(url) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      if top_level == "image" {
        { "type": "image", "source": { "type": "url", "url": url } }
      } else if media_type == "application/pdf" || media_type == "text/plain" {
        if media_type == "application/pdf" {
          append_unique_beta(beta_features, "pdfs-2024-09-25")
        }
        anthropic_document(
          { "type": "url", "url": url },
          resolved_filename,
          scoped_options,
        )
      } else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="Anthropic file media type: \{media_type}",
        )
      }
    }
    @provider.V4FileData(value) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, value,
      )
      if top_level == "image" {
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": full_media_type,
            "data": value,
          },
        }
      } else if full_media_type == "application/pdf" {
        append_unique_beta(beta_features, "pdfs-2024-09-25")
        anthropic_document(
          { "type": "base64", "media_type": "application/pdf", "data": value },
          resolved_filename,
          scoped_options,
        )
      } else if media_type == "text/plain" {
        anthropic_document(
          {
            "type": "text",
            "media_type": "text/plain",
            "data": @provider_utils.decode_base64_text(value),
          },
          resolved_filename,
          scoped_options,
        )
      } else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="Anthropic file media type: \{full_media_type}",
        )
      }
    }
  }
}

///|
fn anthropic_v4_user_content(
  content : Array[@provider.LanguageModelV4PromptPart],
  message_options : Map[String, Json],
  provider_name : String,
  beta_features : Array[String],
) -> Array[Json] raise {
  let result : Array[Json] = []
  for index, part in content {
    let part_options = anthropic_v4_prompt_part_options(part)
    let converted = match part {
      @provider.V4PromptText(text~, ..) => text_content(text)
      @provider.V4PromptFile(data~, media_type~, filename~, ..) =>
        anthropic_v4_file_content(
          data, media_type, filename, part_options, provider_name, beta_features,
        )
      _ =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="non-text/file content in an Anthropic user message",
        )
    }
    result.push(
      with_anthropic_v4_message_cache_control(
        with_anthropic_cache_control(converted, part_options, provider_name),
        part_options,
        message_options,
        index == content.length() - 1,
        provider_name,
      ),
    )
  }
  result
}

///|
fn anthropic_v4_system_content(
  text : String,
  provider_options : Map[String, Json],
  provider_name : String,
  warnings : Array[@provider.Warning],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> (Array[Json], Int) {
  let tool_changes = anthropic_tool_changes(
    provider_options, provider_name, warnings, tool_name_mapping,
  )
  let content : Array[Json] = []
  if text != "" || tool_changes.length() == 0 {
    content.push(
      with_anthropic_cache_control(
        text_content(text),
        provider_options,
        provider_name,
      ),
    )
  }
  for change in tool_changes {
    content.push(change)
  }
  (content, tool_changes.length())
}

///|
fn anthropic_v4_tool_call_content(
  call : @provider.ToolCall,
  provider_name : String,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  let input = tool_input(call)
  if !call.provider_executed {
    let fields : Map[String, Json] = Map([
      ("type", Json::string("tool_use")),
      ("id", Json::string(call.id)),
      ("name", Json::string(call.name)),
      ("input", input),
    ])
    let scoped = resolve_anthropic_prompt_options(
      call.provider_metadata,
      provider_name,
    )
    match scoped.get("caller") {
      Some(value) => fields["caller"] = anthropic_wire_json(value)
      None => ()
    }
    return Some(Json::object(fields))
  }
  let provider_tool_name = tool_name_mapping.to_provider_tool_name(call.name)
  let scoped = resolve_anthropic_prompt_options(
    call.provider_metadata,
    provider_name,
  )
  if scoped.get("type") == Some(Json::string("mcp-tool-use")) {
    match scoped.get("serverName") {
      Some(String(server_name)) =>
        Some({
          "type": "mcp_tool_use",
          "id": call.id,
          "name": call.name,
          "input": input,
          "server_name": server_name,
        })
      _ => {
        warnings.push(
          @provider.Warning::Other(
            message="mcp tool use server name is required and must be a string",
          ),
        )
        None
      }
    }
  } else if provider_tool_name == "code_execution" ||
    provider_tool_name == "web_fetch" ||
    provider_tool_name == "web_search" ||
    provider_tool_name == "tool_search_tool_regex" ||
    provider_tool_name == "tool_search_tool_bm25" ||
    provider_tool_name == "advisor" {
    Some({
      "type": "server_tool_use",
      "id": call.id,
      "name": provider_tool_name,
      "input": if provider_tool_name == "advisor" {
        Json::empty_object()
      } else {
        input
      },
    })
  } else {
    warnings.push(
      @provider.Warning::Other(
        message="provider executed tool call for tool \{call.name} is not supported",
      ),
    )
    None
  }
}

///|
fn anthropic_v4_assistant_content(
  content : Array[@provider.LanguageModelV4PromptPart],
  message_options : Map[String, Json],
  send_reasoning : Bool,
  provider_name : String,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  warnings : Array[@provider.Warning],
) -> Array[Json] raise {
  let result : Array[Json] = []
  for index, part in content {
    let part_options = anthropic_v4_prompt_part_options(part)
    let converted : Json? = match part {
      @provider.V4PromptText(text~, ..) => {
        let value = if anthropic_v4_text_kind(part_options, provider_name) ==
          "compaction" {
          ({ "type": "compaction", "content": text } : Json)
        } else {
          with_anthropic_citations(
            text_content(text),
            part_options,
            provider_name,
          )
        }
        Some(value)
      }
      @provider.V4PromptReasoning(text~, ..) =>
        if !send_reasoning {
          warnings.push(
            @provider.Warning::Other(
              message="sending reasoning content is disabled for this model",
            ),
          )
          None
        } else {
          match anthropic_reasoning_signature(part_options, provider_name) {
            Some(signature) =>
              Some({
                "type": "thinking",
                "thinking": text,
                "signature": signature,
              })
            None =>
              match
                anthropic_v4_redacted_reasoning_data(
                  part_options, provider_name,
                ) {
                Some(data) =>
                  Some({ "type": "redacted_thinking", "data": data })
                None => {
                  warnings.push(
                    @provider.Warning::Other(
                      message="unsupported Anthropic reasoning metadata",
                    ),
                  )
                  None
                }
              }
          }
        }
      @provider.V4PromptToolCall(call) =>
        anthropic_v4_tool_call_content(
          call, provider_name, tool_name_mapping, warnings,
        )
      @provider.V4PromptToolApprovalRequest(_) => {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="toolApprovalRequest",
            details="Anthropic Messages does not expose a generic tool approval request prompt block.",
          ),
        )
        None
      }
      _ =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="unsupported content in an Anthropic assistant message",
        )
    }
    match converted {
      Some(value) =>
        result.push(
          with_anthropic_v4_message_cache_control(
            with_anthropic_cache_control(value, part_options, provider_name),
            part_options,
            message_options,
            index == content.length() - 1,
            provider_name,
          ),
        )
      None => ()
    }
  }
  if result.length() == 0 {
    result.push(text_content(""))
  }
  result
}

///|
fn anthropic_v4_tool_content(
  content : Array[@provider.LanguageModelV4PromptPart],
  message_options : Map[String, Json],
  provider_name : String,
  beta_features : Array[String],
  warnings : Array[@provider.Warning],
) -> Array[Json] raise {
  let result : Array[Json] = []
  for index, part in content {
    match part {
      @provider.V4PromptToolResult(tool_result) => {
        let part_options = tool_result.provider_options
        result.push(
          with_anthropic_v4_message_cache_control(
            with_anthropic_cache_control(
              anthropic_tool_result_to_json(
                tool_result, provider_name, beta_features,
              ),
              part_options,
              provider_name,
            ),
            part_options,
            message_options,
            index == content.length() - 1,
            provider_name,
          ),
        )
      }
      @provider.V4PromptToolApprovalResponse(_) =>
        warnings.push(
          @provider.Warning::Unsupported(
            feature="toolApprovalResponse",
            details="Anthropic Messages does not expose a generic tool approval response wire block; the response was ignored.",
          ),
        )
      _ =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="non-result content in an Anthropic tool message",
        )
    }
  }
  result
}

///|
/// Convert a V4 prompt without constructing LanguageModelMessage values.
fn convert_v4_prompt_to_anthropic(
  prompt : @provider.LanguageModelV4Prompt,
  provider_name : String,
  send_reasoning : Bool,
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> AnthropicV4PromptConversion raise {
  let system : Array[Json] = []
  let messages : Array[AnthropicWireMessage] = []
  let beta_features : Array[String] = []
  let warnings : Array[@provider.Warning] = []
  let mut saw_non_system = false
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, provider_options~) => {
        let (converted, tool_change_count) = anthropic_v4_system_content(
          content, provider_options, provider_name, warnings, tool_name_mapping,
        )
        if !saw_non_system {
          for part in converted {
            match part {
              { "type": "tool_addition", .. }
              | { "type": "tool_removal", .. } => ()
              _ => system.push(part)
            }
          }
          if tool_change_count > 0 {
            warnings.push(
              @provider.Warning::Other(
                message="tool changes on the initial system message are not supported by Anthropic and were ignored.",
              ),
            )
          }
        } else {
          append_wire_message(messages, "system", converted)
          append_unique_beta(
            beta_features, "mid-conversation-system-2026-04-07",
          )
          if tool_change_count > 0 {
            append_unique_beta(
              beta_features, "mid-conversation-tool-changes-2026-07-01",
            )
          }
        }
      }
      @provider.V4UserMessage(content~, provider_options~) => {
        saw_non_system = true
        append_wire_message(
          messages,
          "user",
          anthropic_v4_user_content(
            content, provider_options, provider_name, beta_features,
          ),
        )
      }
      @provider.V4AssistantMessage(content~, provider_options~) => {
        saw_non_system = true
        append_wire_message(
          messages,
          "assistant",
          anthropic_v4_assistant_content(
            content, provider_options, send_reasoning, provider_name, tool_name_mapping,
            warnings,
          ),
        )
      }
      @provider.V4ToolMessage(content~, provider_options~) => {
        saw_non_system = true
        append_wire_message(
          messages,
          "user",
          anthropic_v4_tool_content(
            content, provider_options, provider_name, beta_features, warnings,
          ),
        )
      }
    }
  }
  { system, messages, beta_features, warnings }
}

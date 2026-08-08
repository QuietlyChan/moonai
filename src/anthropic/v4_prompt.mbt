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
    @provider.V4PromptToolCall(call) => call.provider_options
    @provider.V4PromptToolResult(result) => result.provider_options
    @provider.V4PromptToolApprovalResponse(response) =>
      response.provider_options
  }
}

///|
fn anthropic_v4_tool_result_output_options(
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
fn with_anthropic_v4_message_cache_control(
  content : Json,
  part_options : Map[String, Json],
  message_options : Map[String, Json],
  is_last_part : Bool,
  provider_name : String,
  validator : AnthropicCacheControlValidator,
  part_context : String,
  message_context : String,
) -> Json {
  let cache_control = match
    validator.get_cache_control(part_options, provider_name, part_context, true) {
    Some(value) => Some(value)
    None if is_last_part =>
      validator.get_cache_control(
        message_options, provider_name, message_context, true,
      )
    None => None
  }
  match content {
    { "type": String(kind), .. } if kind == "thinking" => {
      ignore(
        validator.get_cache_control(
          part_options, provider_name, "thinking block", false,
        ),
      )
      content
    }
    { "type": String(kind), .. } if kind == "redacted_thinking" => {
      ignore(
        validator.get_cache_control(
          part_options, provider_name, "redacted thinking block", false,
        ),
      )
      content
    }
    { "type": String("container_upload"), .. } => content
    _ => with_anthropic_cache_control_value(content, cache_control)
  }
}

///|
fn with_anthropic_v4_tool_result_cache_control(
  content : Json,
  tool_result : @provider.LanguageModelV4ToolResultPart,
  message_options : Map[String, Json],
  is_last_part : Bool,
  provider_name : String,
  validator : AnthropicCacheControlValidator,
) -> Json {
  let mut cache_control = validator.get_cache_control(
    tool_result.provider_options,
    provider_name,
    "tool result part",
    true,
  )
  if cache_control is None {
    cache_control = validator.get_cache_control(
      anthropic_v4_tool_result_output_options(tool_result.output),
      provider_name,
      "tool result output",
      true,
    )
  }
  if cache_control is None && is_last_part {
    cache_control = validator.get_cache_control(
      message_options, provider_name, "tool result message", true,
    )
  }
  with_anthropic_cache_control_value(content, cache_control)
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
    @provider.V4FileBytes(value) =>
      anthropic_v4_file_content(
        @provider.V4FileData(@provider_utils.convert_bytes_to_base64(value)),
        media_type,
        filename,
        provider_options,
        provider_name,
        beta_features,
      )
  }
}

///|
fn anthropic_v4_user_content(
  content : Array[@provider.LanguageModelV4PromptPart],
  message_options : Map[String, Json],
  provider_name : String,
  beta_features : Array[String],
  validator : AnthropicCacheControlValidator,
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
        converted,
        part_options,
        message_options,
        index == content.length() - 1,
        provider_name,
        validator,
        "user message part",
        "user message",
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
  validator : AnthropicCacheControlValidator,
) -> (Array[Json], Int) {
  let tool_changes = anthropic_tool_changes(
    provider_options, provider_name, warnings, tool_name_mapping,
  )
  let content : Array[Json] = []
  if text != "" || tool_changes.length() == 0 {
    content.push(
      with_anthropic_cache_control_value(
        text_content(text),
        validator.get_cache_control(
          provider_options, provider_name, "system message", true,
        ),
      ),
    )
  }
  for change in tool_changes {
    content.push(change)
  }
  (content, tool_changes.length())
}

///|
fn anthropic_v4_tool_input(input : Json) -> Json {
  match input {
    Object(_) => input
    value => { "rawInvalidInput": value }
  }
}

///|
fn anthropic_v4_tool_call_content(
  call : @provider.LanguageModelV4ToolCallPart,
  provider_name : String,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  warnings : Array[@provider.Warning],
) -> Json? {
  let input = anthropic_v4_tool_input(call.input)
  if !call.provider_executed {
    let fields : Map[String, Json] = Map([
      ("type", Json::string("tool_use")),
      ("id", Json::string(call.tool_call_id)),
      ("name", Json::string(call.tool_name)),
      ("input", input),
    ])
    let scoped = resolve_anthropic_prompt_options(
      call.provider_options,
      provider_name,
    )
    match scoped.get("caller") {
      Some(value) => fields["caller"] = anthropic_wire_json(value)
      None => ()
    }
    return Some(Json::object(fields))
  }
  let provider_tool_name = tool_name_mapping.to_provider_tool_name(
    call.tool_name,
  )
  let scoped = resolve_anthropic_prompt_options(
    call.provider_options,
    provider_name,
  )
  if scoped.get("type") == Some(Json::string("mcp-tool-use")) {
    match scoped.get("serverName") {
      Some(String(server_name)) =>
        Some({
          "type": "mcp_tool_use",
          "id": call.tool_call_id,
          "name": call.tool_name,
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
  } else if provider_tool_name == "code_execution" {
    let (wire_name, wire_input) = match input {
      Object(fields) =>
        match fields.get("type") {
          Some(String(kind)) if kind == "bash_code_execution" ||
            kind == "text_editor_code_execution" => (kind, input)
          Some(String("programmatic-tool-call")) => {
            let stripped = @provider.copy_provider_metadata(fields)
            stripped.remove("type")
            ("code_execution", Json::object(stripped))
          }
          _ => ("code_execution", input)
        }
      _ => ("code_execution", input)
    }
    Some({
      "type": "server_tool_use",
      "id": call.tool_call_id,
      "name": wire_name,
      "input": wire_input,
    })
  } else if provider_tool_name == "web_fetch" ||
    provider_tool_name == "web_search" ||
    provider_tool_name == "tool_search_tool_regex" ||
    provider_tool_name == "tool_search_tool_bm25" ||
    provider_tool_name == "advisor" {
    Some({
      "type": "server_tool_use",
      "id": call.tool_call_id,
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
        message="provider executed tool call for tool \{call.tool_name} is not supported",
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
  beta_features : Array[String],
  tool_name_mapping : @provider_utils.ToolNameMapping,
  warnings : Array[@provider.Warning],
  validator : AnthropicCacheControlValidator,
) -> Array[Json] raise {
  let result : Array[Json] = []
  for index, part in content {
    match part {
      @provider.V4PromptToolResult(tool_result) => {
        match
          anthropic_v4_tool_result_to_json(
            tool_result, provider_name, beta_features, warnings, tool_name_mapping,
          ) {
          Some(value) =>
            result.push(
              with_anthropic_v4_tool_result_cache_control(
                value,
                tool_result,
                message_options,
                index == content.length() - 1,
                provider_name,
                validator,
              ),
            )
          None => ()
        }
        continue
      }
      _ => ()
    }
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
      _ =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="unsupported content in an Anthropic assistant message",
        )
    }
    match converted {
      Some(value) =>
        result.push(
          with_anthropic_v4_message_cache_control(
            value,
            part_options,
            message_options,
            index == content.length() - 1,
            provider_name,
            validator,
            "assistant message part",
            "assistant message",
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
fn anthropic_v4_tool_result_content_part(
  part : @provider.LanguageModelV4ToolResultContentPart,
  provider_name : String,
  beta_features : Array[String],
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match part {
    @provider.V4ToolResultTextContent(text~, ..) => Some(text_content(text))
    @provider.V4ToolResultFileContent(data~, media_type~, provider_options~, ..) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      match data {
        @provider.V4FileUrl(url) =>
          Some(
            if top_level == "image" {
              (
                { "type": "image", "source": { "type": "url", "url": url } } :
                Json)
            } else {
              (
                { "type": "document", "source": { "type": "url", "url": url } } :
                Json)
            },
          )
        @provider.V4FileData(value) => {
          let full_media_type = @provider_utils.resolve_full_media_type(
            media_type, value,
          )
          if top_level == "image" {
            Some({
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": full_media_type,
                "data": value,
              },
            })
          } else if full_media_type == "application/pdf" {
            append_unique_beta(beta_features, "pdfs-2024-09-25")
            Some({
              "type": "document",
              "source": {
                "type": "base64",
                "media_type": "application/pdf",
                "data": value,
              },
            })
          } else {
            warnings.push(
              @provider.Other(
                message="unsupported tool content part type: file with media type: \{media_type}",
              ),
            )
            None
          }
        }
        @provider.V4FileBytes(value) =>
          anthropic_v4_tool_result_content_part(
            @provider.V4ToolResultFileContent(
              data=@provider.V4FileData(
                @provider_utils.convert_bytes_to_base64(value),
              ),
              media_type~,
              filename=None,
              provider_options~,
            ),
            provider_name,
            beta_features,
            warnings,
          )
        @provider.V4FileReference(_) | @provider.V4FileText(_) => {
          let data_type = if data is @provider.V4FileReference(_) {
            "reference"
          } else {
            "text"
          }
          warnings.push(
            @provider.Other(
              message="unsupported tool content part type: file with data type: \{data_type}",
            ),
          )
          None
        }
      }
    }
    @provider.V4ToolResultCustomContent(provider_options~) => {
      let scoped = resolve_anthropic_prompt_options(
        provider_options, provider_name,
      )
      match (scoped.get("type"), scoped.get("toolName")) {
        (Some(String("tool-reference")), Some(String(tool_name))) =>
          Some({ "type": "tool_reference", "tool_name": tool_name })
        _ => {
          warnings.push(
            @provider.Other(message="unsupported custom tool content part"),
          )
          None
        }
      }
    }
  }
}

///|
fn anthropic_v4_tool_result_content(
  output : @provider.LanguageModelV4ToolResultOutput,
  provider_name : String,
  beta_features : Array[String],
  warnings : Array[@provider.Warning],
) -> Json raise {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..)
    | @provider.V4ToolResultErrorText(value~, ..) => Json::string(value)
    @provider.V4ToolResultExecutionDenied(reason~, ..) =>
      Json::string(reason.unwrap_or("Tool call execution denied."))
    @provider.V4ToolResultJsonOutput(value~, ..)
    | @provider.V4ToolResultErrorJson(value~, ..) =>
      Json::string(value.stringify())
    @provider.V4ToolResultContentOutput(value~, ..) => {
      let converted : Array[Json] = []
      for part in value {
        match
          anthropic_v4_tool_result_content_part(
            part, provider_name, beta_features, warnings,
          ) {
          Some(content) => converted.push(content)
          None => ()
        }
      }
      Json::array(converted)
    }
  }
}

///|
fn anthropic_v4_advisor_tool_result(
  result : @provider.LanguageModelV4ToolResultPart,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  let output = match result.output {
    @provider.V4ToolResultJsonOutput(value~, ..)
    | @provider.V4ToolResultErrorJson(value~, ..) => value
    _ => {
      warnings.push(
        @provider.Warning::Other(
          message="provider executed advisor result must use a JSON output",
        ),
      )
      return None
    }
  }
  @provider_utils.validate_json_schema(
    anthropic_advisor_20260301_output_schema(),
    output,
  )
  let content : Json = match output {
    { "type": "advisor_result", "text": String(text), .. } =>
      { "type": "advisor_result", "text": text }
    {
      "type": "advisor_redacted_result",
      "encryptedContent": String(encrypted_content),
      ..
    } =>
      {
        "type": "advisor_redacted_result",
        "encrypted_content": encrypted_content,
      }
    { "type": "advisor_tool_result_error", "errorCode": String(error_code), .. } =>
      { "type": "advisor_tool_result_error", "error_code": error_code }
    _ => fail("validated Anthropic advisor result has an unknown shape")
  }
  Some({
    "type": "advisor_tool_result",
    "tool_use_id": result.tool_call_id,
    "content": content,
  })
}

///|
fn anthropic_v4_tool_result_to_json(
  result : @provider.LanguageModelV4ToolResultPart,
  provider_name : String,
  beta_features : Array[String],
  warnings : Array[@provider.Warning],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Json? raise {
  let provider_tool_name = tool_name_mapping.to_provider_tool_name(
    result.tool_name,
  )
  if provider_tool_name == "advisor" {
    return anthropic_v4_advisor_tool_result(result, warnings)
  }
  if anthropic_is_special_provider_tool_result(provider_tool_name) {
    return anthropic_v4_provider_tool_result(
      result, provider_tool_name, warnings,
    )
  }
  let is_error = match result.output {
    @provider.V4ToolResultErrorText(..) | @provider.V4ToolResultErrorJson(..) =>
      true
    _ => false
  }
  Some(
    Json::object(
      Map(
        [
          ("type", Json::string("tool_result")),
          ("tool_use_id", Json::string(result.tool_call_id)),
          (
            "content",
            anthropic_v4_tool_result_content(
              result.output,
              provider_name,
              beta_features,
              warnings,
            ),
          ),
          ..if is_error {
            [("is_error", Json::boolean(true))]
          },
        ],
      ),
    ),
  )
}

///|
fn anthropic_v4_tool_content(
  content : Array[@provider.LanguageModelV4PromptPart],
  message_options : Map[String, Json],
  provider_name : String,
  beta_features : Array[String],
  warnings : Array[@provider.Warning],
  tool_name_mapping : @provider_utils.ToolNameMapping,
  validator : AnthropicCacheControlValidator,
) -> Array[Json] raise {
  let result : Array[Json] = []
  for index, part in content {
    match part {
      @provider.V4PromptToolResult(tool_result) =>
        match
          anthropic_v4_tool_result_to_json(
            tool_result, provider_name, beta_features, warnings, tool_name_mapping,
          ) {
          Some(value) =>
            result.push(
              with_anthropic_v4_tool_result_cache_control(
                value,
                tool_result,
                message_options,
                index == content.length() - 1,
                provider_name,
                validator,
              ),
            )
          None => ()
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
/// Anthropic requires provider-executed blocks to precede regular tool uses.
/// Thinking blocks are ordering barriers, so each surrounding segment is
/// reordered independently.
fn move_anthropic_tool_use_blocks_to_end(content : Array[Json]) -> Unit {
  let reordered : Array[Json] = []
  let segment : Array[Json] = []
  let flush_segment = () => {
    for part in segment {
      if !(part is { "type": String("tool_use"), .. }) {
        reordered.push(part)
      }
    }
    for part in segment {
      if part is { "type": String("tool_use"), .. } {
        reordered.push(part)
      }
    }
    segment.clear()
  }
  for part in content {
    match part {
      { "type": String(kind), .. } if kind == "thinking" ||
        kind == "redacted_thinking" => {
        flush_segment()
        reordered.push(part)
      }
      _ => segment.push(part)
    }
  }
  flush_segment()
  content.clear()
  for part in reordered {
    content.push(part)
  }
}

///|
/// Flush one contiguous system-message block using the same hoisting rules as
/// the Anthropic provider. The first block is always the top-level system
/// prompt. A later plain-text block is also hoisted when no top-level system
/// prompt has been established yet; tool changes keep the block inline.
fn append_anthropic_v4_system_block(
  system : Array[Json],
  messages : Array[AnthropicWireMessage],
  beta_features : Array[String],
  warnings : Array[@provider.Warning],
  content : Array[Json],
  tool_change_count : Int,
  is_first_block : Bool,
  system_is_set : Bool,
) -> Bool {
  if is_first_block || (!system_is_set && tool_change_count == 0) {
    for part in content {
      if part is { "type": String("text"), .. } {
        system.push(part)
      }
    }
    if tool_change_count > 0 {
      warnings.push(
        @provider.Warning::Other(
          message="tool changes on the initial system message are not supported by Anthropic. Configure the initial tool set via the tools option instead. The tool changes have been ignored.",
        ),
      )
    }
    true
  } else {
    append_wire_message(messages, "system", content)
    append_unique_beta(beta_features, "mid-conversation-system-2026-04-07")
    if tool_change_count > 0 {
      append_unique_beta(
        beta_features, "mid-conversation-tool-changes-2026-07-01",
      )
    }
    system_is_set
  }
}

///|
/// Convert a V4 prompt without constructing LanguageModelMessage values.
fn convert_v4_prompt_to_anthropic(
  prompt : @provider.LanguageModelV4Prompt,
  provider_name : String,
  send_reasoning : Bool,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  validator : AnthropicCacheControlValidator,
) -> AnthropicV4PromptConversion raise {
  let system : Array[Json] = []
  let messages : Array[AnthropicWireMessage] = []
  let beta_features : Array[String] = []
  let warnings : Array[@provider.Warning] = []
  let pending_system_content : Array[Json] = []
  let mut pending_system_tool_change_count = 0
  let mut has_pending_system = false
  let mut system_is_set = false
  let mut saw_block = false
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, provider_options~) => {
        let (converted, tool_change_count) = anthropic_v4_system_content(
          content, provider_options, provider_name, warnings, tool_name_mapping,
          validator,
        )
        has_pending_system = true
        pending_system_tool_change_count = pending_system_tool_change_count +
          tool_change_count
        for part in converted {
          pending_system_content.push(part)
        }
      }
      _ => {
        if has_pending_system {
          system_is_set = append_anthropic_v4_system_block(
            system,
            messages,
            beta_features,
            warnings,
            pending_system_content,
            pending_system_tool_change_count,
            !saw_block,
            system_is_set,
          )
          pending_system_content.clear()
          pending_system_tool_change_count = 0
          has_pending_system = false
          saw_block = true
        }
        saw_block = true
        match message {
          @provider.V4UserMessage(content~, provider_options~) =>
            append_wire_message(
              messages,
              "user",
              anthropic_v4_user_content(
                content, provider_options, provider_name, beta_features, validator,
              ),
            )
          @provider.V4AssistantMessage(content~, provider_options~) =>
            append_wire_message(
              messages,
              "assistant",
              anthropic_v4_assistant_content(
                content, provider_options, send_reasoning, provider_name, beta_features,
                tool_name_mapping, warnings, validator,
              ),
            )
          @provider.V4ToolMessage(content~, provider_options~) =>
            append_wire_message(
              messages,
              "user",
              anthropic_v4_tool_content(
                content, provider_options, provider_name, beta_features, warnings,
                tool_name_mapping, validator,
              ),
            )
          @provider.V4SystemMessage(..) => ()
        }
      }
    }
  }
  if has_pending_system {
    system_is_set = append_anthropic_v4_system_block(
      system,
      messages,
      beta_features,
      warnings,
      pending_system_content,
      pending_system_tool_change_count,
      !saw_block,
      system_is_set,
    )
  }
  trim_final_anthropic_assistant_text(messages)
  for message in messages {
    if message.role == "assistant" {
      move_anthropic_tool_use_blocks_to_end(message.content)
    }
  }
  { system, messages, beta_features, warnings }
}

///|
/// Convert a V4 prompt into Cohere v2 chat messages. Non-image file parts
/// become `documents` entries consumed via RAG citations.
fn cohere_convert_messages(
  prompt : @provider.LanguageModelV4Prompt,
  documents : Array[Json],
  warnings : Array[@provider.Warning],
) -> Array[Json] raise {
  let messages : Array[Json] = []
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, ..) =>
        messages.push({ "role": "system", "content": content })
      @provider.V4UserMessage(content~, ..) => {
        let parts : Array[Json] = []
        let mut text_only = ""
        let mut has_image = false
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) if text != "" => {
              parts.push({ "type": "text", "text": text })
              text_only = text_only + text
            }
            @provider.V4PromptFile(data~, media_type~, ..) => {
              let top_level = media_type.split("/").to_array().get(0)
              if top_level == Some("image") {
                has_image = true
                match cohere_file_url(data, media_type) {
                  Some(url) =>
                    parts.push({
                      "type": "image_url",
                      "image_url": { "url": url },
                    })
                  None => ()
                }
              } else {
                match data {
                  @provider.V4FileText(text) =>
                    documents.push({ "data": { "text": text } })
                  @provider.V4FileData(payload) =>
                    documents.push({ "data": { "text": payload } })
                  _ =>
                    raise @provider.UnsupportedFunctionalityError(
                      functionality="file parts with provider references",
                    )
                }
              }
            }
            _ => ()
          }
        }
        if has_image {
          messages.push({ "role": "user", "content": Json::array(parts) })
        } else {
          messages.push({ "role": "user", "content": text_only })
        }
      }
      @provider.V4AssistantMessage(content~, ..) => {
        let text_parts : Array[String] = []
        let tool_calls : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) => text_parts.push(text)
            @provider.V4PromptToolCall(call_part) =>
              tool_calls.push({
                "id": call_part.tool_call_id,
                "type": "function",
                "function": {
                  "name": call_part.tool_name,
                  "arguments": call_part.input.stringify(),
                },
              })
            _ => ()
          }
        }
        let builder = StringBuilder()
        for part in text_parts {
          builder.write_string(part)
        }
        let text = builder.to_string()
        let fields : Map[String, Json] = Map([
          ("role", Json::string("assistant")),
        ])
        if tool_calls.length() > 0 {
          fields["tool_calls"] = Json::array(tool_calls)
        } else {
          fields["content"] = Json::string(text)
        }
        messages.push(Json::object(fields))
      }
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result_part) => {
              let content_value = match result_part.output {
                @provider.V4ToolResultTextOutput(value~, ..) => value
                @provider.V4ToolResultErrorText(value~, ..) => value
                @provider.V4ToolResultExecutionDenied(reason~, ..) =>
                  reason.unwrap_or("Tool call execution denied.")
                @provider.V4ToolResultJsonOutput(value~, ..) =>
                  value.stringify()
                @provider.V4ToolResultErrorJson(value~, ..) => value.stringify()
                @provider.V4ToolResultContentOutput(..) => ""
              }
              messages.push({
                "role": "tool",
                "content": content_value,
                "tool_call_id": result_part.tool_call_id,
              })
            }
            _ => ()
          }
        }
    }
  }
  ignore(warnings)
  messages
}

///|
/// Map V4 tools onto Cohere's function shape; tool choice narrows to
/// REQUIRED for named tools since Cohere has no per-tool choice.
fn cohere_prepare_tools(
  tools : Array[@provider.LanguageModelV4Tool],
  tool_choice : @provider.LanguageModelV4ToolChoice?,
  warnings : Array[@provider.Warning],
) -> (Array[Json], String?) {
  let cohere_tools : Array[Json] = []
  for tool in tools {
    match tool {
      @provider.V4FunctionTool(definition) => {
        let function : Map[String, Json] = Map([
          ("name", Json::string(definition.name)),
        ])
        if definition.description is Some(value) {
          function["description"] = Json::string(value)
        }
        function["parameters"] = definition.input_schema
        cohere_tools.push({
          "type": "function",
          "function": Json::object(function),
        })
      }
      @provider.V4ProviderTool(value) =>
        warnings.push(
          @provider.Warning::unsupported("provider-defined tool \{value.id}"),
        )
    }
  }
  let choice : String? = match tool_choice {
    Some(@provider.V4ToolChoiceNone) => Some("NONE")
    Some(@provider.V4ToolChoiceRequired) => Some("REQUIRED")
    Some(@provider.V4ToolChoiceTool(name)) => {
      let named : Array[Json] = []
      for tool in cohere_tools {
        if tool is { "function": { "name": String(value), .. }, .. } &&
          value == name {
          named.push(tool)
        }
      }
      cohere_tools.clear()
      for tool in named {
        cohere_tools.push(tool)
      }
      Some("REQUIRED")
    }
    _ => None
  }
  (cohere_tools, choice)
}

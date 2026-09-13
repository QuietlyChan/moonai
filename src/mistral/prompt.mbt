///|
/// Convert a V4 prompt into Mistral chat messages. Text and image parts map
/// to Mistral's content-part shapes; PDF references become `document_url`.
fn mistral_convert_messages(
  prompt : @provider.LanguageModelV4Prompt,
) -> Array[Json] raise {
  let messages : Array[Json] = []
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, ..) =>
        messages.push({ "role": "system", "content": content })
      @provider.V4UserMessage(content~, ..) => {
        let parts : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) =>
              parts.push({ "type": "text", "text": text })
            @provider.V4PromptFile(data~, media_type~, ..) => {
              let url = match data {
                @provider.V4FileUrl(url) => url
                @provider.V4FileData(payload) =>
                  // Inline file data is already Base64 in the V4 contract.
                  "data:\{media_type};base64,\{payload}"
                _ =>
                  raise @provider.UnsupportedFunctionalityError(
                    functionality="file parts with provider references",
                  )
              }
              let top_level = media_type.split("/").to_array().get(0)
              if top_level == Some("application") {
                parts.push({ "type": "document_url", "document_url": url })
              } else {
                parts.push({ "type": "image_url", "image_url": url })
              }
            }
            _ =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="user content part",
              )
          }
        }
        if parts.length() == 1 {
          match parts[0] {
            { "type": "text", "text": String(text), .. } =>
              messages.push({ "role": "user", "content": text })
            _ =>
              messages.push({ "role": "user", "content": Json::array(parts) })
          }
        } else {
          messages.push({ "role": "user", "content": Json::array(parts) })
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
        let text = text_parts.get(0).unwrap_or("")
        if tool_calls.length() > 0 {
          let fields : Map[String, Json] = Map([
            ("role", Json::string("assistant")),
            ("tool_calls", Json::array(tool_calls)),
          ])
          if text != "" {
            fields["content"] = Json::string(text)
          }
          messages.push(Json::object(fields))
        } else {
          messages.push({ "role": "assistant", "content": text })
        }
      }
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result_part) =>
              messages.push({
                "role": "tool",
                "tool_call_id": result_part.tool_call_id,
                "content": mistral_tool_output_to_json(result_part.output),
              })
            _ => ()
          }
        }
    }
  }
  messages
}

///|
/// Map V4 tools and tool choice onto Mistral's function-calling wire shape.
fn mistral_prepare_tools(
  tools : Array[@provider.LanguageModelV4Tool],
  tool_choice : @provider.LanguageModelV4ToolChoice?,
  warnings : Array[@provider.Warning],
) -> (Array[Json], Json?) {
  let mistral_tools : Array[Json] = []
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
        mistral_tools.push({
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
  let mistral_choice : Json? = match tool_choice {
    Some(@provider.V4ToolChoiceAuto) => Some(Json::string("auto"))
    Some(@provider.V4ToolChoiceNone) => Some(Json::string("none"))
    Some(@provider.V4ToolChoiceRequired) => Some(Json::string("any"))
    Some(@provider.V4ToolChoiceTool(name)) =>
      Some({ "type": "function", "function": { "name": name } })
    None => None
  }
  (mistral_tools, mistral_choice)
}

///|
fn mistral_map_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("stop") => @provider.V4FinishStop
    Some("length") => @provider.V4FinishLength
    Some("tool_calls") => @provider.V4FinishToolCalls
    Some("error") => @provider.V4FinishError
    _ => @provider.V4FinishOther
  }
  { unified, raw, }
}

///|
fn mistral_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
/// Extract the response identity triple Mistral sends on every payload.
fn mistral_response_metadata(value : Json) -> @provider.ResponseMetadata {
  let mut id : String? = None
  let mut model_id : String? = None
  let mut created_at : Int? = None
  if value is Object(fields) {
    match fields.get("id") {
      Some(String(text)) => id = Some(text)
      _ => ()
    }
    match fields.get("model") {
      Some(String(text)) => model_id = Some(text)
      _ => ()
    }
    match fields.get("created") {
      Some(Number(value, ..)) => created_at = Some(value.to_int())
      _ => ()
    }
  }
  { ..@provider.ResponseMetadata::empty(), id, model_id, created_at, }
}

///|
fn mistral_tool_output_to_json(
  output : @provider.LanguageModelV4ToolResultOutput,
) -> Json raise {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..) => Json::string(value)
    @provider.V4ToolResultJsonOutput(value~, ..) =>
      Json::string(value.stringify())
    @provider.V4ToolResultErrorText(value~, ..) => Json::string(value)
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="tool result output",
      )
  }
}

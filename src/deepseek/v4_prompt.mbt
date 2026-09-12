///|
priv struct DeepSeekV4PromptConversion {
  messages : Array[Json]
  warnings : Array[@provider.Warning]
}

///|
fn deepseek_v4_prompt_part_type(
  part : @provider.LanguageModelV4PromptPart,
) -> String {
  match part {
    @provider.V4PromptText(..) => "text"
    @provider.V4PromptReasoning(..) => "reasoning"
    @provider.V4PromptReasoningFile(..) => "reasoning-file"
    @provider.V4PromptCustom(..) => "custom"
    @provider.V4PromptFile(..) => "file"
    @provider.V4PromptToolCall(_) => "tool-call"
    @provider.V4PromptToolResult(_) => "tool-result"
    @provider.V4PromptToolApprovalResponse(_) => "tool-approval-response"
  }
}

///|
fn deepseek_v4_file_data_json(data : @provider.LanguageModelV4FileData) -> Json {
  match data {
    @provider.V4FileData(value) => { "type": "data", "data": value }
    @provider.V4FileBytes(value) =>
      { "type": "data", "data": @base64.encode(value) }
    @provider.V4FileUrl(value) => { "type": "url", "url": value }
    @provider.V4FileReference(reference) => {
      let entries : Map[String, Json] = Map([])
      for provider_name in reference.providers() {
        if reference.get(provider_name) is Some(id) {
          entries[provider_name] = Json::string(id)
        }
      }
      { "type": "reference", "reference": Json::object(entries) }
    }
    @provider.V4FileText(value) => { "type": "text", "text": value }
  }
}

///|
fn deepseek_v4_tool_result_content_json(
  part : @provider.LanguageModelV4ToolResultContentPart,
) -> Json {
  match part {
    @provider.V4ToolResultTextContent(text~, provider_options~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("text")),
            ("text", Json::string(text)),
            ..if provider_options.length() > 0 {
              [("providerOptions", Json::object(provider_options))]
            },
          ],
        ),
      )
    @provider.V4ToolResultFileContent(
      data~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      Json::object(
        Map(
          [
            ("type", Json::string("file")),
            ("data", deepseek_v4_file_data_json(data)),
            ("mediaType", Json::string(media_type)),
            ..if filename is Some(value) {
              [("filename", Json::string(value))]
            },
            ..if provider_options.length() > 0 {
              [("providerOptions", Json::object(provider_options))]
            },
          ],
        ),
      )
    @provider.V4ToolResultCustomContent(provider_options~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("custom")),
            ..if provider_options.length() > 0 {
              [("providerOptions", Json::object(provider_options))]
            },
          ],
        ),
      )
  }
}

///|
fn deepseek_v4_tool_result_text(
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
          for part in value => deepseek_v4_tool_result_content_json(part)
        ],
      ).stringify()
  }
}

///|
fn deepseek_v4_tool_call_json(
  call : @provider.LanguageModelV4ToolCallPart,
) -> Json {
  {
    "id": call.tool_call_id,
    "type": "function",
    "function": { "name": call.tool_name, "arguments": call.input.stringify() },
  }
}

///|
fn deepseek_v4_assistant_message(
  content : Array[@provider.LanguageModelV4PromptPart],
  include_reasoning : Bool,
  require_reasoning_field : Bool,
  prefix~ : Bool,
) -> Json {
  let text = StringBuilder()
  let reasoning = StringBuilder()
  let mut has_reasoning = false
  let tool_calls : Array[Json] = []
  for part in content {
    match part {
      @provider.V4PromptText(text=value, ..) => text.write_string(value)
      @provider.V4PromptReasoning(text=value, ..) if include_reasoning => {
        reasoning.write_string(value)
        has_reasoning = true
      }
      @provider.V4PromptToolCall(call) =>
        tool_calls.push(deepseek_v4_tool_call_json(call))
      _ => ()
    }
  }
  let fields : Map[String, Json] = Map([
    ("role", Json::string("assistant")),
    ("content", Json::string(text.to_string())),
  ])
  if has_reasoning {
    fields["reasoning_content"] = Json::string(reasoning.to_string())
  } else if require_reasoning_field {
    fields["reasoning_content"] = Json::string("")
  }
  if prefix {
    // Assistant prefix continuation (beta): the model continues from this
    // message instead of starting a new one.
    fields["prefix"] = Json::boolean(true)
  }
  if tool_calls.length() > 0 {
    fields["tool_calls"] = Json::array(tool_calls)
  }
  Json::object(fields)
}

///|
/// Read a string option from a message's DeepSeek provider options.
fn deepseek_message_provider_string(
  options : Map[String, Json],
  field~ : String,
) -> String? {
  match options.get("deepseek") {
    Some(Object(values)) =>
      match values.get(field) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn deepseek_message_provider_bool(
  options : Map[String, Json],
  field~ : String,
) -> Bool? {
  match options.get("deepseek") {
    Some(Object(values)) =>
      match values.get(field) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
/// Convert the provider V4 prompt directly to DeepSeek Chat messages.
fn convert_v4_prompt_to_deepseek(
  prompt : @provider.LanguageModelV4Prompt,
  response_format : @provider.LanguageModelV4ResponseFormat,
  model_id : String,
  supports_structured_outputs : Bool,
) -> DeepSeekV4PromptConversion {
  let messages : Array[Json] = []
  let warnings : Array[@provider.Warning] = []
  match response_format {
    @provider.V4ResponseJson({ schema: None, .. }) =>
      messages.push({ "role": "system", "content": "Return JSON." })
    @provider.V4ResponseJson({ schema: Some(schema), .. }) if !supports_structured_outputs => {
      messages.push({
        "role": "system",
        "content": "Return JSON that conforms to the following schema: " +
        schema.stringify(),
      })
      warnings.push(
        @provider.Warning::Compatibility(
          feature="responseFormat JSON schema",
          details="JSON response schema is injected into the system message.",
        ),
      )
    }
    _ => ()
  }
  let mut last_user_index = -1
  for index, message in prompt.messages {
    if message is @provider.V4UserMessage(..) {
      last_user_index = index
    }
  }
  let is_v4 = is_deepseek_v4_model(model_id)
  for index, message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, provider_options~) => {
        let fields : Map[String, Json] = Map([
          ("role", Json::string("system")),
          ("content", Json::string(content)),
        ])
        // Message-level name (AI SDK #19399).
        match deepseek_message_provider_string(provider_options, field="name") {
          Some(name) => fields["name"] = Json::string(name)
          None => ()
        }
        messages.push(Json::object(fields))
      }
      @provider.V4UserMessage(content~, provider_options~) => {
        let text = StringBuilder()
        for part in content {
          match part {
            @provider.V4PromptText(text=value, ..) => text.write_string(value)
            _ =>
              warnings.push(
                @provider.Warning::Unsupported(
                  feature="user message part type: \{deepseek_v4_prompt_part_type(part)}",
                  details="DeepSeek Chat accepts text user content only.",
                ),
              )
          }
        }
        let fields : Map[String, Json] = Map([
          ("role", Json::string("user")),
          ("content", Json::string(text.to_string())),
        ])
        match deepseek_message_provider_string(provider_options, field="name") {
          Some(name) => fields["name"] = Json::string(name)
          None => ()
        }
        messages.push(Json::object(fields))
      }
      @provider.V4AssistantMessage(content~, provider_options~) => {
        let prefix = deepseek_message_provider_bool(
          provider_options,
          field="prefix",
        )
        if prefix == Some(true) && index != prompt.messages.length() - 1 {
          warnings.push(
            @provider.Warning::Unsupported(
              feature="assistant prefix completion",
              details="DeepSeek assistant prefix completion requires the prefixed assistant message to be the final message; the prefix flag was ignored.",
            ),
          )
        }
        messages.push(
          deepseek_v4_assistant_message(
            content,
            is_v4 || index > last_user_index,
            is_v4,
            prefix=prefix == Some(true) && index == prompt.messages.length() - 1,
          ),
        )
      }
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result) =>
              messages.push({
                "role": "tool",
                "tool_call_id": result.tool_call_id,
                "content": deepseek_v4_tool_result_text(result.output),
              })
            @provider.V4PromptToolApprovalResponse(_) => ()
            _ =>
              warnings.push(
                @provider.Warning::Unsupported(
                  feature="tool message part type: \{deepseek_v4_prompt_part_type(part)}",
                  details="DeepSeek tool messages accept tool results only.",
                ),
              )
          }
        }
    }
  }
  { messages, warnings, }
}

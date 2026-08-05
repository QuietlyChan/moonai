///|
priv struct PreparedDeepSeekRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn deepseek_message_content(message : @provider.LanguageModelMessage) -> String {
  if message.parts.length() == 0 {
    message.content
  } else {
    let content = StringBuilder::new()
    for part in message.parts {
      match part.without_provider_options() {
        @provider.Text(value) => content.write_string(value)
        _ => ()
      }
    }
    content.to_string()
  }
}

///|
/// Read reasoning carried either by the legacy message field or by V4
/// assistant content parts. Content parts take precedence when present so a
/// prompt bridge cannot duplicate the same reasoning text.
fn deepseek_assistant_reasoning(
  message : @provider.LanguageModelMessage,
) -> String? {
  let parts_reasoning = StringBuilder::new()
  let mut has_part_reasoning = false
  for part in message.parts {
    match part.without_provider_options() {
      @provider.Reasoning(value) => {
        has_part_reasoning = true
        parts_reasoning.write_string(value)
      }
      _ => ()
    }
  }
  if has_part_reasoning {
    Some(parts_reasoning.to_string())
  } else {
    message.reasoning_content
  }
}

///|
/// Serialize a structured tool result using DeepSeek's textual tool output
/// contract. JSON and multimodal outputs are represented as compact JSON.
fn deepseek_tool_result_text(
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
fn deepseek_tool_result_message(
  result : @provider.LanguageModelToolResult,
) -> Json {
  {
    "role": "tool",
    "tool_call_id": result.tool_call_id,
    "content": deepseek_tool_result_text(result.output),
  }
}

///|
/// Expand all structured tool results carried by one normalized tool message.
/// The Chat Completions wire format permits only one call id per message.
fn deepseek_tool_messages(
  message : @provider.LanguageModelMessage,
) -> Array[Json] {
  let result : Array[Json] = []
  for part in message.parts {
    match part.without_provider_options() {
      @provider.ToolResultPart(value) =>
        result.push(deepseek_tool_result_message(value))
      @provider.ToolApprovalResponsePart(_) => ()
      _ => ()
    }
  }
  result
}

///|
fn deepseek_tool_call_json(call : @provider.ToolCall) -> Json {
  {
    "id": call.id,
    "type": "function",
    "function": { "name": call.name, "arguments": call.arguments },
  }
}

///|
fn deepseek_message_json(
  message : @provider.LanguageModelMessage,
  index : Int,
  last_user_index : Int,
  is_v4 : Bool,
) -> Json {
  match message.role {
    @provider.System => { "role": "system", "content": message.content }
    @provider.User =>
      { "role": "user", "content": deepseek_message_content(message) }
    @provider.Tool(tool_call_id) =>
      {
        "role": "tool",
        "tool_call_id": tool_call_id,
        "content": deepseek_message_content(message),
      }
    @provider.Assistant => {
      let fields : Map[String, Json] = Map([
        ("role", Json::string("assistant")),
        ("content", Json::string(deepseek_message_content(message))),
      ])
      if deepseek_assistant_reasoning(message) is Some(reasoning) &&
        (is_v4 || index > last_user_index) {
        fields["reasoning_content"] = Json::string(reasoning)
      } else if is_v4 {
        fields["reasoning_content"] = Json::string("")
      }
      let tool_calls = message.effective_tool_calls()
      if tool_calls.length() > 0 {
        fields["tool_calls"] = Json::array(
          [
            for call in tool_calls => deepseek_tool_call_json(call)
          ],
        )
      }
      Json::object(fields)
    }
  }
}

///|
fn deepseek_tool_json(tool : @provider.ToolDefinition) -> Json? {
  match tool {
    @provider.FunctionTool(name~, description~, input_schema~, strict~, ..) => {
      let function : Map[String, Json] = Map([("name", Json::string(name))])
      if description is Some(value) {
        function["description"] = Json::string(value)
      }
      function["parameters"] = input_schema
      if strict is Some(value) {
        function["strict"] = Json::boolean(value)
      }
      Some({ "type": "function", "function": Json::object(function) })
    }
    @provider.ProviderTool(..) => None
  }
}

///|
fn deepseek_tool_choice(choice : @provider.ToolChoice) -> Json {
  match choice {
    @provider.Auto => Json::string("auto")
    @provider.NoTool => Json::string("none")
    @provider.Required => Json::string("required")
    @provider.Named(name) =>
      { "type": "function", "function": { "name": name } }
  }
}

///|
fn deepseek_finish_reason(value : String) -> @provider.FinishReason {
  match value {
    "stop" => @provider.Stop
    "length" => @provider.Length
    "content_filter" => @provider.ContentFilter
    "tool_calls" => @provider.ToolCalls
    "insufficient_system_resource" => @provider.Error
    other => @provider.Unknown(other)
  }
}

///|
fn prepare_deepseek_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name : String,
  stream : Bool,
  supports_thinking : Bool,
  supports_structured_outputs : Bool,
) -> PreparedDeepSeekRequest {
  let parsed = parse_deepseek_options(options.provider_options, provider_name)
  let warnings = parsed.warnings
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="DeepSeek Chat does not support topK.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="DeepSeek does not support deterministic seed control.",
      ),
    )
  }
  for message in options.messages {
    for part in message.parts {
      let supported = match part.without_provider_options() {
        @provider.Text(_) => true
        @provider.Reasoning(_) => message.role is @provider.Assistant
        @provider.ToolCallPart(_) => message.role is @provider.Assistant
        @provider.ToolResultPart(_) => message.role is @provider.Tool(_)
        @provider.ToolApprovalResponsePart(_) =>
          message.role is @provider.Tool(_)
        _ => false
      }
      if !supported {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="multimodal message part",
            details="DeepSeek Chat accepts text message content only; the part was ignored.",
          ),
        )
      }
    }
  }
  let tools : Array[Json] = []
  for tool in options.tools {
    match deepseek_tool_json(tool) {
      Some(value) => tools.push(value)
      None =>
        warnings.push(
          @provider.Warning::Unsupported(
            feature="provider-defined tool",
            details="DeepSeek Chat accepts function tools only.",
          ),
        )
    }
  }
  let messages : Array[Json] = []
  let is_v4 = model_id.contains("deepseek-v4")
  let mut last_user_index = -1
  for index, message in options.messages {
    if message.role is @provider.User {
      last_user_index = index
    }
  }
  match options.response_format {
    @provider.JsonResponse({ schema: None, .. }) =>
      messages.push({ "role": "system", "content": "Return JSON." })
    @provider.JsonResponse({ schema: Some(schema), .. }) if !supports_structured_outputs => {
      messages.push({
        "role": "system",
        "content": "Return JSON that conforms to the following schema: " +
        schema.stringify(),
      })
      warnings.push(
        @provider.Warning::Compatibility(
          feature="responseFormat JSON schema",
          details="JSON response schema was injected into the system message.",
        ),
      )
    }
    _ => ()
  }
  for index, message in options.messages {
    if message.role is @provider.Tool(_) && message.parts.length() > 0 {
      let tool_messages = deepseek_tool_messages(message)
      if tool_messages.length() > 0 {
        for tool_message in tool_messages {
          messages.push(tool_message)
        }
        continue
      }
    }
    messages.push(deepseek_message_json(message, index, last_user_index, is_v4))
  }
  let thinking_type = if !supports_thinking {
    None
  } else {
    match parsed.options.thinking_type {
      Some(value) => Some(value)
      None =>
        match options.reasoning_effort {
          @provider.Disabled => Some("disabled")
          @provider.ProviderDefault => None
          _ => Some("enabled")
        }
    }
  }
  let reasoning_effort = match parsed.options.reasoning_effort {
    Some(value) => Some(value)
    None => deepseek_reasoning_effort(options.reasoning_effort, warnings)
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(model_id)),
    ("messages", Json::array(messages)),
  ])
  if stream {
    fields["stream"] = Json::boolean(true)
    fields["stream_options"] = { "include_usage": true }
  }
  match options.max_output_tokens {
    Some(value) => fields["max_tokens"] = Json::number(value.to_double())
    None => ()
  }
  match options.temperature {
    Some(value) => fields["temperature"] = Json::number(value)
    None => ()
  }
  match options.top_p {
    Some(value) => fields["top_p"] = Json::number(value)
    None => ()
  }
  match options.frequency_penalty {
    Some(value) => fields["frequency_penalty"] = Json::number(value)
    None => ()
  }
  match options.presence_penalty {
    Some(value) => fields["presence_penalty"] = Json::number(value)
    None => ()
  }
  if options.stop_sequences.length() > 0 {
    fields["stop"] = Json::array(
      [
        for value in options.stop_sequences => Json::string(value)
      ],
    )
  }
  match options.response_format {
    @provider.JsonResponse(config) =>
      match config.schema {
        Some(schema) if supports_structured_outputs => {
          let json_schema : Map[String, Json] = Map([
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(parsed.options.strict_json_schema)),
          ])
          if config.description is Some(value) {
            json_schema["description"] = Json::string(value)
          }
          fields["response_format"] = {
            "type": "json_schema",
            "json_schema": Json::object(json_schema),
          }
        }
        _ => fields["response_format"] = { "type": "json_object" }
      }
    _ => ()
  }
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    match options.tool_choice {
      Some(choice) => fields["tool_choice"] = deepseek_tool_choice(choice)
      None => ()
    }
  }
  match thinking_type {
    Some(value) => fields["thinking"] = { "type": value }
    None => ()
  }
  if thinking_type != Some("disabled") {
    match reasoning_effort {
      Some(value) => fields["reasoning_effort"] = Json::string(value)
      None => ()
    }
  }
  { body: Json::object(fields), warnings }
}

///|
/// Encode a DeepSeek Chat Completions request without transport configuration.
pub fn encode_deepseek_chat_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  stream? : Bool = false,
  provider_name? : String = "deepseek.chat",
  supports_thinking? : Bool = true,
  supports_structured_outputs? : Bool = false,
) -> Json {
  prepare_deepseek_request(
    model_id, options, provider_name, stream, supports_thinking, supports_structured_outputs,
  ).body
}

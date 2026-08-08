///|
fn available_tool_names(tools : @provider_utils.ToolSet) -> Array[String] {
  [
    for entry in tools.iter2() => entry.0
  ]
}

///|
fn no_such_tool_message(
  tool_name : String,
  tools : @provider_utils.ToolSet,
) -> String {
  let available = available_tool_names(tools)
  let suffix = if available.length() == 0 {
    "No tools are available."
  } else {
    "Available tools: " + available.join(", ") + "."
  }
  "No such tool \"\{tool_name}\". \{suffix}"
}

///|
fn invalid_tool_call(
  call : @provider.LanguageModelV4ToolCall,
  input : Json,
  message : String,
) -> GenerateTextToolCall {
  {
    tool_call_id: call.tool_call_id,
    tool_name: call.tool_name,
    input,
    input_text: call.input,
    provider_executed: call.provider_executed,
    // AI SDK exposes invalid calls through its dynamic-call branch because
    // their input no longer satisfies a statically known schema.
    dynamic: true,
    invalid: true,
    error: Some(message),
    provider_metadata: @provider.copy_provider_metadata(call.provider_metadata),
  }
}

///|
fn parse_tool_call(
  call : @provider.LanguageModelV4ToolCall,
  tools : @provider_utils.ToolSet,
) -> GenerateTextToolCall {
  let input = if call.input.trim().is_empty() {
    Json::empty_object()
  } else {
    @json.parse(call.input) catch {
      error =>
        return invalid_tool_call(
          call,
          Json::string(call.input),
          "Invalid input for tool \"\{call.tool_name}\": " +
          @debug.to_string(error),
        )
    }
  }
  let tool = match tools.get(call.tool_name) {
    Some(value) => value
    None => {
      // Provider-executed dynamic tools are intentionally allowed to be
      // absent from the client tool set.
      if call.provider_executed && call.dynamic {
        return {
          tool_call_id: call.tool_call_id,
          tool_name: call.tool_name,
          input,
          input_text: call.input,
          provider_executed: true,
          dynamic: true,
          invalid: false,
          error: None,
          provider_metadata: @provider.copy_provider_metadata(
            call.provider_metadata,
          ),
        }
      }
      return invalid_tool_call(
        call,
        input,
        no_such_tool_message(call.tool_name, tools),
      )
    }
  }
  match tool.input_schema() {
    Some(schema) =>
      @provider_utils.validate_json_schema(schema, input) catch {
        @provider_utils.JsonSchemaValidationError(path~, message~) =>
          return invalid_tool_call(
            call,
            input,
            "Invalid input for tool \"\{call.tool_name}\" at \{path}: \{message}",
          )
      }
    None => ()
  }
  {
    tool_call_id: call.tool_call_id,
    tool_name: call.tool_name,
    input,
    input_text: call.input,
    provider_executed: call.provider_executed,
    dynamic: tool.is_dynamic() || call.dynamic,
    invalid: false,
    error: None,
    provider_metadata: @provider.copy_provider_metadata(call.provider_metadata),
  }
}

///|
fn parse_tool_calls(
  content : Array[@provider.LanguageModelV4Content],
  tools : @provider_utils.ToolSet,
) -> Array[GenerateTextToolCall] {
  let calls : Array[GenerateTextToolCall] = []
  for part in content {
    match part {
      @provider.V4ToolCallOutput(call) =>
        calls.push(parse_tool_call(call, tools))
      _ => ()
    }
  }
  calls
}

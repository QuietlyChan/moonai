///|
fn chat_response_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn append_chat_tool_calls(
  values : Array[Json],
  output : Array[@moonai.ToolCall],
) -> Unit {
  for index, value in values {
    match value {
      {
        "id": String(id),
        "function": { "name": String(name), "arguments": String(arguments), .. },
        ..
      } => output.push(@moonai.ToolCall::new(id~, name~, arguments~))
      {
        "function": { "name": String(name), "arguments": String(arguments), .. },
        ..
      } =>
        output.push(
          @moonai.ToolCall::new(id="tool-call-\{index}", name~, arguments~),
        )
      _ => ()
    }
  }
}

///|
/// Decode one non-streaming OpenAI-compatible Chat Completions response.
pub fn decode_chat_response(json : Json) -> @moonai.ChatResponse raise {
  if chat_response_error_message(json) is Some(message) {
    fail("OpenAI-compatible request failed: \{message}")
  }
  let choice = match json {
    { "choices": [choice, ..], .. } => choice
    { "choices": [], .. } => fail("OpenAI-compatible response has no choices")
    _ => fail("OpenAI-compatible response has no valid choice")
  }
  let message = match choice {
    { "message": Object(_) as value, .. } => value
    _ => fail("OpenAI-compatible response choice has no message")
  }
  let raw_finish_reason = match choice {
    { "finish_reason": String(reason), .. } => Some(reason)
    _ => None
  }
  let text = match message {
    { "content": String(value), .. } => value
    _ => ""
  }
  let reasoning = match message {
    { "reasoning_content": String(value), .. } => value
    { "reasoning": String(value), .. } => value
    _ => ""
  }
  let tool_calls : Array[@moonai.ToolCall] = []
  match message {
    { "tool_calls": Array(values), .. } =>
      append_chat_tool_calls(values, tool_calls)
    _ => ()
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => usage_from_json(value)
    _ => @moonai.Usage::zero()
  }
  let finish_reason = match raw_finish_reason {
    Some(value) => @moonai.FinishReason::from_openai(value)
    None =>
      if tool_calls.length() > 0 {
        @moonai.ToolCalls
      } else {
        @moonai.Stop
      }
  }
  { text, reasoning, tool_calls, usage, finish_reason }
}

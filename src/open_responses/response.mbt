///|
fn append_response_text_parts(
  parts : Array[Json],
  output : StringBuilder,
) -> Unit {
  for part in parts {
    match part {
      { "type": "output_text", "text": String(value), .. } =>
        output.write_string(value)
      { "type": "refusal", "refusal": String(value), .. } =>
        output.write_string(value)
      _ => ()
    }
  }
}

///|
fn append_reasoning_parts(parts : Array[Json], output : StringBuilder) -> Unit {
  for part in parts {
    match part {
      { "type": "reasoning_text", "text": String(value), .. }
      | { "type": "summary_text", "text": String(value), .. } =>
        output.write_string(value)
      _ => ()
    }
  }
}

///|
fn response_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
/// Decode one non-streaming Open Responses response into the normalized result.
pub fn decode_responses_response(json : Json) -> @moonai.ChatResponse raise {
  if response_error_message(json) is Some(message) {
    fail("Open Responses request failed: \{message}")
  }
  let incomplete_reason = match json {
    { "incomplete_details": { "reason": String(reason), .. }, .. } => reason
    _ => ""
  }
  let no_output_detail = if incomplete_reason != "" {
    incomplete_reason
  } else {
    match json {
      { "status": String(status), .. } => status
      _ => ""
    }
  }
  let output = match json {
    { "output": Array(items), .. } => items
    _ if no_output_detail != "" =>
      fail("Open Responses returned no output (\{no_output_detail})")
    _ => fail("Open Responses returned no output")
  }
  let text = StringBuilder::new()
  let reasoning = StringBuilder::new()
  let tool_calls : Array[@moonai.ToolCall] = []
  for item in output {
    match item {
      { "type": "message", "content": Array(parts), .. } =>
        append_response_text_parts(parts, text)
      { "type": "reasoning", "content": Array(parts), .. } =>
        append_reasoning_parts(parts, reasoning)
      { "type": "reasoning", "summary": Array(parts), .. } =>
        append_reasoning_parts(parts, reasoning)
      {
        "type": "function_call",
        "call_id": String(call_id),
        "name": String(name),
        "arguments": String(arguments),
        ..
      } => tool_calls.push(@moonai.ToolCall::new(id=call_id, name~, arguments~))
      _ => ()
    }
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => usage_from_json(value)
    _ => @moonai.Usage::zero()
  }
  let finish_reason = match json {
    { "status": "failed", .. } => @moonai.Error
    _ => map_finish_reason(incomplete_reason, tool_calls.length() > 0)
  }
  {
    text: text.to_string(),
    reasoning: reasoning.to_string(),
    tool_calls,
    usage,
    finish_reason,
  }
}

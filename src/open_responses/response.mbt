///|
fn response_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
fn missing_responses_output_message(json : Json) -> String? {
  match json {
    { "output": Array(_), .. } => None
    { "incomplete_details": { "reason": String(reason), .. }, .. } =>
      Some("Responses API returned no output (\{reason})")
    { "status": String(status), .. } if status != "" =>
      Some("Responses API returned no output (\{status})")
    _ => Some("Responses API returned no output")
  }
}

///|
priv struct DecodedOpenResponsesResponse {
  content : Array[@provider.GeneratedContent]
  usage : @provider.Usage
  raw_usage : Json?
  finish_reason : @provider.FinishReason
  finish_reason_raw : String?
  response_metadata : @provider.ResponseMetadata?
}

///|
/// Preserve the optional counters used by the V4 contract instead of
/// collapsing a missing Open Responses usage object into zeroes.
fn open_responses_v4_usage_from_json(
  raw_usage : Json?,
) -> @provider.LanguageModelV4Usage {
  @provider.LanguageModelV4Usage::from_token_usage_json(raw_usage)
}

///|
fn decode_open_responses_response_data(
  json : Json,
  id_generator? : @provider_utils.IdGenerator,
) -> DecodedOpenResponsesResponse raise {
  if response_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="Open Responses request failed: \{message}",
      data=json,
    )
  }
  let incomplete_reason = match json {
    { "incomplete_details": { "reason": String(reason), .. }, .. } => reason
    _ => ""
  }
  let output = match json {
    { "output": Array(items), .. } => items
    _ =>
      raise @provider.InvalidResponseDataError(
        message=missing_responses_output_message(json).unwrap(),
        data=json,
      )
  }
  let content : Array[@provider.GeneratedContent] = []
  let mut has_tool_calls = false
  let generate_id = id_generator.unwrap_or(@provider_utils.generate_id)
  for item in output {
    match item {
      { "type": "message", "content": Array(parts), .. } =>
        for part in parts {
          match part {
            { "type": "output_text", "text": String(value), .. }
            | { "type": "refusal", "refusal": String(value), .. } =>
              content.push(@provider.GeneratedContent::text(value))
            _ => ()
          }
        }
      { "type": "reasoning", "content": Array(parts), .. } =>
        for part in parts {
          match part {
            { "type": "reasoning_text", "text": String(value), .. }
            | { "type": "summary_text", "text": String(value), .. } =>
              content.push(@provider.GeneratedContent::reasoning(value))
            _ => ()
          }
        }
      { "type": "reasoning", "summary": Array(parts), .. } =>
        for part in parts {
          match part {
            { "type": "reasoning_text", "text": String(value), .. }
            | { "type": "summary_text", "text": String(value), .. } =>
              content.push(@provider.GeneratedContent::reasoning(value))
            _ => ()
          }
        }
      {
        "type": "function_call",
        "call_id": String(call_id),
        "name": String(name),
        "arguments": String(arguments),
        ..
      } => {
        let call = @provider.ToolCall::new(id=call_id, name~, arguments~)
        content.push(@provider.GeneratedContent::tool_call(call))
        has_tool_calls = true
      }
      {
        "type": "function_call",
        "name": String(name),
        "arguments": String(arguments),
        ..
      } => {
        let call_id = generate_id()
        let call = @provider.ToolCall::new(id=call_id, name~, arguments~)
        content.push(@provider.GeneratedContent::tool_call(call))
        has_tool_calls = true
      }
      _ => ()
    }
  }
  let raw_usage = match json {
    { "usage": value, .. } if !(value is Null) => Some(value)
    _ => None
  }
  let usage = match raw_usage {
    Some(value) => usage_from_json(value)
    None => @provider.Usage::zero()
  }
  let finish_reason = match json {
    { "status": "failed", .. } => @provider.Error
    _ => map_finish_reason(incomplete_reason, has_tool_calls)
  }
  let finish_reason_raw = match json {
    { "status": "failed", "error": { "code": String(value), .. }, .. } =>
      Some(value)
    { "status": "failed", .. } => Some("failed")
    _ => if incomplete_reason == "" { None } else { Some(incomplete_reason) }
  }
  let response_metadata = @provider.ResponseMetadata::from_json(json)
  {
    content,
    usage,
    raw_usage,
    finish_reason,
    finish_reason_raw,
    response_metadata: if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
  }
}

///|
/// Decode one non-streaming Open Responses response into the normalized result.
pub fn decode_responses_response(
  json : Json,
  id_generator? : @provider_utils.IdGenerator,
) -> @provider.ChatResponse raise {
  let decoded = decode_open_responses_response_data(json, id_generator?)
  @provider.ChatResponse::from_content(
    decoded.content,
    decoded.usage,
    decoded.finish_reason,
  ).with_diagnostics(None, decoded.response_metadata, Map([]), [])
}

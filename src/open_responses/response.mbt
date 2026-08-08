///|
fn response_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
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
  content : Array[@provider.LanguageModelV4Content]
  usage : @provider.LanguageModelV4Usage
  finish_reason : @provider.LanguageModelV4FinishReason
  response : @provider.ResponseMetadata?
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
  id_generator~ : @provider_utils.IdGenerator,
) -> DecodedOpenResponsesResponse raise {
  if response_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="Open Responses request failed: \{message}",
      data=json,
    )
  }
  let incomplete_reason = match json {
    { "incomplete_details": { "reason": String(reason), .. }, .. } =>
      Some(reason)
    _ => None
  }
  let output = match json {
    { "output": Array(items), .. } => items
    _ =>
      raise @provider.InvalidResponseDataError(
        message=missing_responses_output_message(json).unwrap(),
        data=json,
      )
  }
  let content : Array[@provider.LanguageModelV4Content] = []
  let mut has_tool_calls = false
  for item in output {
    match item {
      { "type": "message", "content": Array(parts), .. } =>
        for part in parts {
          match part {
            { "type": "output_text", "text": String(value), .. }
            | { "type": "refusal", "refusal": String(value), .. } =>
              content.push(@provider.LanguageModelV4Content::text(value))
            _ => ()
          }
        }
      { "type": "reasoning", "content": Array(parts), .. } =>
        for part in parts {
          match part {
            { "type": "reasoning_text", "text": String(value), .. }
            | { "type": "summary_text", "text": String(value), .. } =>
              content.push(@provider.LanguageModelV4Content::reasoning(value))
            _ => ()
          }
        }
      { "type": "reasoning", "summary": Array(parts), .. } =>
        for part in parts {
          match part {
            { "type": "reasoning_text", "text": String(value), .. }
            | { "type": "summary_text", "text": String(value), .. } =>
              content.push(@provider.LanguageModelV4Content::reasoning(value))
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
        content.push(
          @provider.LanguageModelV4Content::tool_call({
            tool_call_id: call_id,
            tool_name: name,
            input: arguments,
            provider_executed: false,
            dynamic: false,
            provider_metadata: Map([]),
          }),
        )
        has_tool_calls = true
      }
      {
        "type": "function_call",
        "name": String(name),
        "arguments": String(arguments),
        ..
      } => {
        let call_id = id_generator()
        content.push(
          @provider.LanguageModelV4Content::tool_call({
            tool_call_id: call_id,
            tool_name: name,
            input: arguments,
            provider_executed: false,
            dynamic: false,
            provider_metadata: Map([]),
          }),
        )
        has_tool_calls = true
      }
      _ => ()
    }
  }
  let raw_usage = match json {
    { "usage": value, .. } if !(value is Null) => Some(value)
    _ => None
  }
  let finish_reason : @provider.LanguageModelV4FinishReason = {
    unified: match incomplete_reason {
      None =>
        if has_tool_calls {
          @provider.V4FinishToolCalls
        } else {
          @provider.V4FinishStop
        }
      Some("max_output_tokens") => @provider.V4FinishLength
      Some("content_filter") => @provider.V4FinishContentFilter
      Some(_) =>
        if has_tool_calls {
          @provider.V4FinishToolCalls
        } else {
          @provider.V4FinishOther
        }
    },
    raw: incomplete_reason,
  }
  let response_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created_at"),
  )
  {
    content,
    usage: open_responses_v4_usage_from_json(raw_usage),
    finish_reason,
    response: if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
  }
}

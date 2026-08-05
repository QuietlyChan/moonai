///|
fn openai_compatible_thought_signature_metadata(
  json : Json,
  metadata_key : String,
) -> Map[String, Json] {
  match json {
    {
      "extra_content": {
        "google": { "thought_signature": String(signature), .. },
        ..
      },
      ..
    } if signature != "" =>
      Map([(metadata_key, ({ "thoughtSignature": signature } : Json))])
    _ => Map([])
  }
}

///|
fn openai_compatible_prediction_metadata(
  json : Json,
  metadata_key : String,
) -> Map[String, Json] {
  let details : Map[String, Json] = Map([])
  match json {
    {
      "usage": { "completion_tokens_details": Object(completion_details), .. },
      ..
    } => {
      match completion_details.get("accepted_prediction_tokens") {
        Some(Number(value, ..)) =>
          details["acceptedPredictionTokens"] = Json::number(value)
        _ => ()
      }
      match completion_details.get("rejected_prediction_tokens") {
        Some(Number(value, ..)) =>
          details["rejectedPredictionTokens"] = Json::number(value)
        _ => ()
      }
    }
    _ => ()
  }
  if details.length() == 0 {
    Map([])
  } else {
    Map([(metadata_key, Json::object(details))])
  }
}

///|
fn decode_openai_compatible_tool_call(
  json : Json,
  index : Int,
  metadata_key : String,
  id_generator : @provider_utils.IdGenerator,
) -> @provider.ToolCall? {
  guard json is Object(_) else { return None }
  let (name, arguments) = match json {
    {
      "function": { "name": String(name), "arguments": String(arguments), .. },
      ..
    } => (name, arguments)
    _ => return None
  }
  let id = match json {
    { "id": String(value), .. } => value
    _ => {
      let generated = id_generator()
      if generated == "" {
        "tool-call-\{index}"
      } else {
        generated
      }
    }
  }
  Some(
    @provider.ToolCall::new(
      id~,
      name~,
      arguments~,
      provider_metadata=openai_compatible_thought_signature_metadata(
        json, metadata_key,
      ),
    ),
  )
}

///|
/// Decode one non-streaming OpenAI-compatible Chat Completions response.
pub fn decode_chat_response(
  json : Json,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  convert_usage? : (Json) -> @provider.Usage = convert_openai_compatible_chat_usage,
  metadata_key? : String = "openai-compatible",
  id_generator? : @provider_utils.IdGenerator,
) -> @provider.ChatResponse raise {
  if error_structure.message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible request failed: \{message}",
      data=json,
    )
  }
  let choice = match json {
    { "choices": [choice, ..], .. } => choice
    { "choices": [], .. } =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible response has no choices",
        data=json,
      )
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible response has no valid choice",
        data=json,
      )
  }
  let message = match choice {
    { "message": Object(_) as value, .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible response choice has no message",
        data=json,
      )
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
  let content : Array[@provider.GeneratedContent] = []
  let generate_id = id_generator.unwrap_or(@provider_utils.generate_id)
  if text != "" {
    content.push(@provider.GeneratedContent::text(text))
  }
  if reasoning != "" {
    content.push(@provider.GeneratedContent::reasoning(reasoning))
  }
  match message {
    { "tool_calls": Array(values), .. } =>
      for index, value in values {
        match
          decode_openai_compatible_tool_call(
            value, index, metadata_key, generate_id,
          ) {
          Some(call) =>
            content.push(@provider.GeneratedContent::tool_call(call))
          None => ()
        }
      }
    _ => ()
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => convert_usage(value)
    _ => @provider.Usage::zero()
  }
  let finish_reason = match raw_finish_reason {
    Some(value) => @provider.FinishReason::from_openai(value)
    None => @provider.Unknown("")
  }
  let response_metadata = @provider.ResponseMetadata::from_json(json)
  @provider.ChatResponse::from_content(content, usage, finish_reason).with_diagnostics(
    None,
    if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
    openai_compatible_prediction_metadata(json, metadata_key),
    [],
  )
}

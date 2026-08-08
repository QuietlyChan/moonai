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
) -> @provider.LanguageModelV4ToolCall raise {
  guard json is Object(_) else {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible tool call is not an object",
      data=json,
    )
  }
  let (name, arguments) = match json {
    {
      "function": { "name": String(name), "arguments": String(arguments), .. },
      ..
    } => (name, arguments)
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible tool call has no valid function name and arguments",
        data=json,
      )
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
  {
    tool_call_id: id,
    tool_name: name,
    input: arguments,
    provider_executed: false,
    dynamic: false,
    provider_metadata: openai_compatible_thought_signature_metadata(
      json, metadata_key,
    ),
  }
}

///|
fn openai_compatible_v4_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("stop") => @provider.V4FinishStop
    Some("length") => @provider.V4FinishLength
    Some("content_filter") => @provider.V4FinishContentFilter
    Some("function_call") | Some("tool_calls") => @provider.V4FinishToolCalls
    _ => @provider.V4FinishOther
  }
  { unified, raw }
}

///|
priv struct OpenAICompatibleDecodedChatResponse {
  content : Array[@provider.LanguageModelV4Content]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  provider_metadata : Map[String, Json]
  response : @provider.ResponseMetadata?
}

///|
/// Decode one non-streaming OpenAI-compatible Chat Completions response.
fn decode_chat_response(
  json : Json,
  error_structure : OpenAICompatibleErrorStructure,
  convert_usage : OpenAICompatibleUsageConverter,
  metadata_key : String,
  id_generator : @provider_utils.IdGenerator,
  validate_response : OpenAICompatibleJsonValidator,
) -> OpenAICompatibleDecodedChatResponse raise {
  if error_structure.message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible request failed: \{message}",
      data=json,
    )
  }
  if validate_response(json) is Some(message) {
    raise @provider.InvalidResponseDataError(message~, data=json)
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
  match message {
    { "role": String(role), .. } if role != "assistant" =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible response message has invalid role: \{role}",
        data=message,
      )
    _ => ()
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
  let content : Array[@provider.LanguageModelV4Content] = []
  let generate_id = id_generator
  if text != "" {
    content.push(@provider.LanguageModelV4Content::text(text))
  }
  if reasoning != "" {
    content.push(@provider.LanguageModelV4Content::reasoning(reasoning))
  }
  match message {
    { "tool_calls": Array(values), .. } =>
      for index, value in values {
        content.push(
          @provider.LanguageModelV4Content::tool_call(
            decode_openai_compatible_tool_call(
              value, index, metadata_key, generate_id,
            ),
          ),
        )
      }
    _ => ()
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => convert_usage(Some(value))
    _ => convert_usage(None)
  }
  let response_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created"),
  )
  let provider_metadata = @provider.merge_provider_metadata(
    Map([(metadata_key, Json::empty_object())]),
    openai_compatible_prediction_metadata(json, metadata_key),
  )
  {
    content,
    finish_reason: openai_compatible_v4_finish_reason(raw_finish_reason),
    usage,
    provider_metadata,
    response: if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
  }
}

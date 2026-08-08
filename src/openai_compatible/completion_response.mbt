///|
fn convert_openai_compatible_completion_usage(
  usage : Json?,
) -> @provider.LanguageModelV4Usage {
  match usage {
    Some(json) if !(json is Null) => {
      let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
      let output_tokens = @provider_utils.json_int_field(
        json, "completion_tokens",
      )
      {
        input_tokens: {
          total: Some(input_tokens),
          no_cache: Some(input_tokens),
          cache_read: None,
          cache_write: None,
        },
        output_tokens: {
          total: Some(output_tokens),
          text: Some(output_tokens),
          reasoning: None,
        },
        raw: Some(json),
      }
    }
    _ => @provider_utils.create_null_language_model_usage()
  }
}

///|
priv struct OpenAICompatibleDecodedCompletionResponse {
  content : Array[@provider.LanguageModelV4Content]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  response : @provider.ResponseMetadata?
}

///|
/// Decode one non-streaming legacy OpenAI completion response.
fn decode_completion_response(
  json : Json,
  error_structure : OpenAICompatibleErrorStructure,
) -> OpenAICompatibleDecodedCompletionResponse raise {
  if error_structure.message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible completion request failed: \{message}",
      data=json,
    )
  }
  if validate_openai_compatible_completion_response(json) is Some(message) {
    raise @provider.InvalidResponseDataError(message~, data=json)
  }
  let (text, raw_finish_reason) = match json {
    {
      "choices": [
        { "text": String(text), "finish_reason": String(reason), .. },
        ..,
      ],
      ..
    } => (text, Some(reason))
    { "choices": [{ "text": String(text), .. }, ..], .. } => (text, None)
    { "choices": [], .. } =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible completion has no choices",
        data=json,
      )
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible completion response has no valid choice",
        data=json,
      )
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) =>
      convert_openai_compatible_completion_usage(Some(value))
    _ => convert_openai_compatible_completion_usage(None)
  }
  let response_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created"),
  )
  {
    content: if text == "" {
      []
    } else {
      [@provider.LanguageModelV4Content::text(text)]
    },
    finish_reason: openai_compatible_v4_finish_reason(raw_finish_reason),
    usage,
    response: if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
  }
}

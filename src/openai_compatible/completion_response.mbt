///|
/// Decode one non-streaming legacy OpenAI completion response.
pub fn decode_completion_response(
  json : Json,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
) -> @provider.CompletionResponse raise {
  if error_structure.message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible completion request failed: \{message}",
      data=json,
    )
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
      convert_openai_compatible_chat_usage(value)
    _ => @provider.Usage::zero()
  }
  let finish_reason = match raw_finish_reason {
    Some(value) => @provider.FinishReason::from_openai(value)
    None => @provider.Stop
  }
  @provider.CompletionResponse::new(text, usage, finish_reason)
}

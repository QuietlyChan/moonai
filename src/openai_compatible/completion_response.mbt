///|
/// Decode one non-streaming legacy OpenAI completion response.
pub fn decode_completion_response(
  json : Json,
) -> @moonai.CompletionResponse raise {
  if stream_error_message(json) is Some(message) {
    fail("OpenAI-compatible completion request failed: \{message}")
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
    { "choices": [], .. } => fail("OpenAI-compatible completion has no choices")
    _ => fail("OpenAI-compatible completion response has no valid choice")
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => usage_from_json(value)
    _ => @moonai.Usage::zero()
  }
  let finish_reason = match raw_finish_reason {
    Some(value) => @moonai.FinishReason::from_openai(value)
    None => @moonai.Stop
  }
  @moonai.CompletionResponse::new(text, usage, finish_reason)
}

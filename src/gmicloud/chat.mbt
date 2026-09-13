///|
/// GMI's edge nests the backend engine's diagnostic inside `error.details`
/// as a JSON string (`"{\"error\":{\"message\":...}}"`); the default
/// OpenAI-compatible error handling drops it. Prefer the inner diagnostic.
fn gmicloud_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    {
      "error": { "message": String(message), "details": String(details), .. },
      ..
    } => {
      let inner_message = try @json.parse(details) catch {
        _ => None
      } noraise {
        { "error": { "message": String(inner), .. }, .. } if inner.trim() != "" =>
          Some(inner)
        _ => None
      }
      Some(inner_message.unwrap_or(message))
    }
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
fn gmicloud_error_structure() -> @openai_compatible.OpenAICompatibleErrorStructure {
  @openai_compatible.OpenAICompatibleErrorStructure::new(
    error_to_message=gmicloud_error_to_message,
  )
}

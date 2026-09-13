///|
/// Baseten returns two error envelopes: the Model APIs send a bare string
/// (`{ "error": "..." }`), while dedicated deployments pass through their
/// server's OpenAI-shaped object (`{ "error": { "message": ... } }`).
fn baseten_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
fn baseten_error_structure() -> @openai_compatible.OpenAICompatibleErrorStructure {
  @openai_compatible.OpenAICompatibleErrorStructure::new(
    error_to_message=baseten_error_to_message,
  )
}

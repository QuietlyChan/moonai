///|
fn anthropic_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

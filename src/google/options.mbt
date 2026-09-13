///|
/// Google Gemini model ids, e.g. `gemini-2.5-pro`, `gemini-2.5-flash`,
/// `gemini-embedding-001` (https://ai.google.dev/gemini-api/docs/models).
pub type GoogleChatModelId = String

///|
/// Google embedding model ids.
pub type GoogleEmbeddingModelId = String

///|
/// Models path helper: bare ids live under `models/`, tuned models carry
/// their own path segments.
pub fn get_model_path(model_id : String) -> String {
  if model_id.contains("/") {
    model_id
  } else {
    "models/\{model_id}"
  }
}

///|
/// Camel-case spelling of `get_model_path`.
pub fn getModelPath(model_id : String) -> String {
  get_model_path(model_id)
}

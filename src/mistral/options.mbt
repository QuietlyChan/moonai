///|
/// Mistral chat model ids (https://docs.mistral.ai/getting-started/models).
pub type MistralChatModelId = String

///|
/// Mistral embedding model ids, e.g. `mistral-embed`.
pub type MistralEmbeddingModelId = String

///|
/// Mistral speech (voxtral tts) model ids.
pub type MistralSpeechModelId = String

///|
/// Mistral transcription (voxtral) model ids.
pub type MistralTranscriptionModelId = String

///|
/// Model ids that accept the `reasoningEffort` option (magistral family).
fn mistral_supports_reasoning_effort(model_id : String) -> Bool {
  model_id.contains("magistral")
}

///|
/// Provider options accepted under the `mistral` namespace (all optional):
///
/// - `safePrompt` (bool): prefix the conversation with a safety prompt.
/// - `reasoningEffort` (string): `"none" | "high"` for magistral models.
/// - `structuredOutputs` (bool, default true): use json_schema response
///   format when a schema is given.
/// - `strictJsonSchema` (bool, default false): set `strict` on json_schema.
/// - `documentImageLimit` (int): max document images per request.
/// - `documentPageLimit` (int): max document pages per request.
/// - `promptCacheKey` (string): prompt cache key.
/// - `parallelToolCalls` (bool): run tool calls in parallel.

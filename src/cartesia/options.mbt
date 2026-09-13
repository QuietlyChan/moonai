///|
/// Cartesia speech (TTS) model ids, e.g. `sonic-2`, `sonic`.
pub type CartesiaSpeechModelId = String

///|
/// Cartesia transcription (STT) model ids, e.g. `ink-whisper`.
pub type CartesiaTranscriptionModelId = String

///|
/// Cartesia API version sent via the `Cartesia-Version` header.
pub const CARTESIA_API_VERSION : String = "2025-04-16"

///|
/// Provider options accepted under the `cartesia` namespace (all optional):
/// speech — `language` (ISO 639-1), `voice_id` override is carried by the
/// `voice` argument; transcription — `language` (ISO 639-1), `biasing` word
/// list, `timepoint` granularity flags.

///|
/// ElevenLabs speech (TTS) model ids, e.g. `eleven_multilingual_v2`,
/// `eleven_turbo_v2_5`, `eleven_flash_v2_5`.
pub type ElevenLabsSpeechModelId = String

///|
/// ElevenLabs transcription (STT) model ids, e.g. `scribe_v1`.
pub type ElevenLabsTranscriptionModelId = String

///|
/// Provider options accepted under the `elevenlabs` namespace (all optional,
/// wire names as given): `voice_settings` (object), `language_code`,
/// `tag_audio_events`, `num_speakers`, `timestamps_granularity`,
/// `diarize`, `additional_formats`.

///|
test "elevenlabs provider exposes speech and transcription models" {
  let provider = create_elevenlabs(api_key="el-test")
  let speech = provider.speech("eleven_multilingual_v2")
  assert_eq(speech.provider(), "elevenlabs.speech")
  assert_eq(speech.model_id(), "eleven_multilingual_v2")
  let transcription = provider.transcription("scribe_v1")
  assert_eq(transcription.provider(), "elevenlabs.transcription")
  assert_eq(transcription.model_id(), "scribe_v1")
}

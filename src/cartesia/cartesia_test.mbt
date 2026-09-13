///|
test "cartesia provider exposes speech and transcription models" {
  let provider = create_cartesia(api_key="cs-test")
  let speech = provider.speech("sonic-2")
  assert_eq(speech.provider(), "cartesia.speech")
  assert_eq(speech.model_id(), "sonic-2")
  let transcription = provider.transcription("ink-whisper")
  assert_eq(transcription.provider(), "cartesia.transcription")
}

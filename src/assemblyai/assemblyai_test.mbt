///|
test "assemblyai provider exposes transcription models" {
  let provider = create_assemblyai(api_key="aa-test")
  let transcription = provider.transcription("universal-3-pro")
  assert_eq(transcription.provider(), "assemblyai.transcription")
  assert_eq(transcription.model_id(), "universal-3-pro")
  assert_eq(transcription.specification_version(), "v4")
}

///|
test "official OpenAI transcription falls back to word timestamps" {
  let response = decode_openai_transcription_response(
    {
      "text": "hello world",
      "language": "unknown-language",
      "words": [
        { "word": "hello", "start": 0.0, "end": 0.5 },
        { "word": "world", "start": 0.5, "end": 1.0 },
      ],
    },
    "gpt-4o-transcribe",
    "openai.transcription",
    [],
  )
  assert_eq(response.language, None)
  assert_eq(response.segments, [
    @provider.TranscriptionSegment::new(
      text="hello",
      start_second=0.0,
      end_second=0.5,
    ),
    @provider.TranscriptionSegment::new(
      text="world",
      start_second=0.5,
      end_second=1.0,
    ),
  ])
}

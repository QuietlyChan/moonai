///|
test "cartesia speech body nests transcript and voice controls" {
  let body = cartesia_speech_request_body(
    "sonic-2",
    text="hello",
    voice="voice-1",
    language=Some("en"),
    speed=Some(1.1),
    provider_options=Map([]),
  )
  assert_true(
    body
    is {
      "model_id": "sonic-2",
      "transcript": "hello",
      "voice": { "id": "voice-1", .. },
      "language": "en",
      ..
    },
  )
}

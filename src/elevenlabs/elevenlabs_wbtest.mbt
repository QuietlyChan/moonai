///|
test "elevenlabs speech request body maps language and speed" {
  let body = elevenlabs_speech_request_body(
    "eleven_multilingual_v2",
    text="hello world",
    language=Some("en"),
    speed=Some(1.2),
    provider_options=Map([("diarize", Json::boolean(true))]),
  )
  assert_true(
    body
    is {
      "text": "hello world",
      "model_id": "eleven_multilingual_v2",
      "language_code": "en",
      "voice_settings": { "speed": 1.2, .. },
      "diarize": true,
      ..
    },
  )
}

///|
test "elevenlabs error message resolves detail payloads" {
  assert_eq(
    elevenlabs_error_to_message({ "detail": { "message": "bad key" } }),
    Some("bad key"),
  )
  assert_eq(
    elevenlabs_error_to_message({ "detail": "quota exceeded" }),
    Some("quota exceeded"),
  )
}

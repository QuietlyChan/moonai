///|
async test "official OpenAI speech and transcription own their transports" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          if request.path == "/v1/audio/speech" {
            assert_true(
              request.headers.get("authorization") is Some("Bearer test-key"),
            )
            assert_true(
              request.headers.get("x-request") is Some("speech-request"),
            )
            let request_body = body.read_all().text()
            assert_true(request_body.contains("\"model\":\"tts-1\""))
            assert_true(request_body.contains("\"input\":\"Hello MoonBit\""))
            assert_true(request_body.contains("\"voice\":\"nova\""))
            assert_true(request_body.contains("\"response_format\":\"wav\""))
            assert_true(request_body.contains("\"speed\":1.5"))
            assert_true(
              request_body.contains("\"instructions\":\"Speak clearly\""),
            )
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "audio/wav",
              "X-Request-Id": "speech-1",
            })
            connection.write("AUDIO-WAV")
          } else {
            assert_eq(request.path, "/v1/audio/transcriptions")
            assert_true(
              request.headers.get("x-request") is Some("transcribe-request"),
            )
            let request_body = body.read_all().text()
            assert_true(
              request_body.contains("name=\"model\"\r\n\r\nwhisper-1"),
            )
            assert_true(request_body.contains("filename=\"audio.wav\""))
            assert_true(request_body.contains("Content-Type: audio/x-wav"))
            assert_true(request_body.contains("RIFF-WAVE"))
            assert_true(
              request_body.contains(
                "name=\"response_format\"\r\n\r\nverbose_json",
              ),
            )
            assert_true(request_body.contains("name=\"language\"\r\n\r\nen"))
            assert_true(
              request_body.contains("name=\"prompt\"\r\n\r\nMoonBit names"),
            )
            assert_true(
              request_body.contains("name=\"temperature\"\r\n\r\n0.2"),
            )
            assert_true(
              request_body.contains(
                "name=\"timestamp_granularities[]\"\r\n\r\nword",
              ),
            )
            assert_true(
              request_body.contains("name=\"include[]\"\r\n\r\nlogprobs"),
            )
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
              "X-Request-Id": "transcription-1",
            })
            connection.write(
              "{\"text\":\"MoonBit is concise.\",\"language\":\"english\",\"duration\":2.5,\"segments\":[{\"id\":0,\"seek\":0,\"start\":0.0,\"end\":2.5,\"text\":\"MoonBit is concise.\",\"tokens\":[],\"temperature\":0,\"avg_logprob\":-0.1,\"compression_ratio\":1.0,\"no_speech_prob\":0.0}],\"provider_metadata\":{\"openai\":{\"requestId\":\"transcription-1\"}}}",
            )
          }
        },
        max_connections=2,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let speech = @ai.generate_speech(
      provider.speech("tts-1"),
      "Hello MoonBit",
      voice="nova",
      output_format="wav",
      instructions="Speak clearly",
      speed=1.5,
      language="en",
      headers={ "X-Request": "speech-request" },
    )
    match speech.audio {
      @provider.SpeechAudioBytes(data) => assert_eq(data, b"AUDIO-WAV")
      _ => fail("expected binary OpenAI speech data")
    }
    assert_eq(speech.media_type, "audio/wav")
    assert_eq(speech.warnings.length(), 1)
    assert_true(
      speech.warnings[0] is @provider.Unsupported(feature="language", ..),
    )
    assert_eq(speech.response.unwrap().model_id, Some("tts-1"))
    assert_eq(speech.response.unwrap().status_code, Some(200))
    let transcription = @ai.transcribe(
      provider.transcription("whisper-1"),
      audio=@provider.TranscriptionAudio::bytes(b"RIFF-WAVE"),
      media_type="audio/x-wav",
      headers={ "X-Request": "transcribe-request" },
      provider_options={
        "openai": {
          "include": ["logprobs"],
          "language": "en",
          "prompt": "MoonBit names",
          "temperature": 0.2,
          "timestampGranularities": ["word"],
        },
      },
    )
    assert_eq(transcription.text, "MoonBit is concise.")
    assert_eq(transcription.language, Some("en"))
    assert_eq(transcription.duration_seconds, Some(2.5))
    assert_eq(transcription.segments, [
      @provider.TranscriptionSegment::new(
        text="MoonBit is concise.",
        start_second=0.0,
        end_second=2.5,
      ),
    ])
    assert_eq(transcription.response.unwrap().model_id, Some("whisper-1"))
    assert_true(
      transcription.request.unwrap().body.contains(
        "<file name=\"file\" filename=\"audio.wav\" type=\"audio/x-wav\" bytes=9>",
      ),
    )
    assert_false(transcription.request.unwrap().body.contains("RIFF-WAVE"))
    json_inspect(transcription.provider_metadata["openai"], content={
      "requestId": "transcription-1",
    })
  }
}

///|
async test "official OpenAI speech surfaces typed binary API errors" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(400, "Bad Request", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"error\":{\"message\":\"invalid voice\",\"type\":\"invalid_request_error\"}}",
          )
        },
        max_connections=1,
      )
    }
    let model = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    ).speech("tts-1")
    try @ai.generate_speech(model, "hello") catch {
      @provider.APICallError(
        message~,
        status_code~,
        request_body~,
        is_retryable~,
        ..
      ) => {
        assert_eq(message, "invalid voice")
        assert_eq(status_code, 400)
        assert_true(request_body.contains("\"model\":\"tts-1\""))
        assert_false(is_retryable)
      }
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a typed binary API error")
    }
  }
}

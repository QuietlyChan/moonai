///|
test "transcription envelope parses minimal and complete client frames" {
  assert_eq(TRANSCRIPTION_STREAM_START_FRAME_TYPE, "transcription-stream.start")
  assert_eq(
    TRANSCRIPTION_STREAM_AUDIO_DONE_FRAME_TYPE,
    "transcription-stream.audio-done",
  )
  let minimal = parse_transcription_stream_client_frame(
    "{\"type\":\"transcription-stream.start\",\"inputAudioFormat\":{\"type\":\"audio/pcm\"}}",
  )
  match minimal {
    TranscriptionStreamStart(frame) => {
      assert_eq(
        frame.input_audio_format,
        @provider.AudioFormat::new(media_type="audio/pcm"),
      )
      assert_eq(frame.provider_options, None)
      assert_eq(frame.include_raw_chunks, None)
    }
    _ => fail("expected a minimal start frame")
  }
  let complete = TranscriptionStreamStartFrame::new(
    input_audio_format=@provider.AudioFormat::new(
      media_type="audio/pcm",
      sample_rate=16000,
    ),
    provider_options={ "openai": { "language": "en" } },
    include_raw_chunks=true,
  )
  let encoded = serialize_transcription_stream_start_frame(complete)
  match parseTranscriptionStreamClientFrame(encoded) {
    TranscriptionStreamStart(frame) => assert_eq(frame, complete)
    _ => fail("expected a complete start frame")
  }
  assert_eq(
    parse_transcription_stream_client_frame(
      serializeTranscriptionStreamAudioDoneFrame(),
    ),
    TranscriptionStreamAudioDone,
  )
}

///|
test "transcription envelope classifies invalid and unknown client frames" {
  assert_eq(
    parse_transcription_stream_client_frame("{not-json"),
    TranscriptionStreamInvalid("malformed JSON"),
  )
  assert_true(
    parse_transcription_stream_client_frame("[]")
    is TranscriptionStreamInvalid("frame must be a JSON object"),
  )
  assert_true(
    parse_transcription_stream_client_frame(
      "{\"type\":\"transcription-stream.future\"}",
    )
    is TranscriptionStreamUnknown,
  )
  assert_true(
    parse_transcription_stream_client_frame(
      "{\"type\":\"transcription-stream.start\",\"inputAudioFormat\":{\"type\":\"audio/pcm\",\"rate\":\"16000\"}}",
    )
    is TranscriptionStreamInvalid(_),
  )
  assert_true(
    parse_transcription_stream_client_frame(
      "{\"type\":\"transcription-stream.start\",\"inputAudioFormat\":{\"type\":\"audio/pcm\"},\"__proto__\":{\"polluted\":true}}",
    )
    is TranscriptionStreamInvalid("malformed JSON"),
  )
  assert_true(
    parse_transcription_stream_client_frame(
      "{\"type\":\"transcription-stream.start\",\"inputAudioFormat\":{\"type\":\"audio/pcm\"},\"constructor\":{\"prototype\":{\"polluted\":true}}}",
    )
    is TranscriptionStreamInvalid("malformed JSON"),
  )
}

///|
test "transcription envelope round-trips normalized stream parts" {
  let parts : Array[@provider.TranscriptionModelV4StreamPart] = [
    @provider.TranscriptionV4StreamStart(warnings=[
      @provider.Unsupported(feature="topK", details="not supported"),
    ]),
    @provider.TranscriptionV4TranscriptDelta(
      id=Some("segment-1"),
      delta="Hel",
      provider_metadata={ "openai": { "traceId": "trace-1" } },
    ),
    @provider.TranscriptionV4TranscriptPartial(
      id=Some("segment-1"),
      text="Hel",
      start_second=Some(0.0),
      duration_in_seconds=Some(0.5),
      channel_index=Some(0),
      provider_metadata=Map([]),
    ),
    @provider.TranscriptionV4TranscriptFinal(
      id=Some("segment-1"),
      text="Hello",
      start_second=Some(0.0),
      end_second=Some(1.0),
      channel_index=Some(0),
      provider_metadata=Map([]),
    ),
    @provider.TranscriptionV4Finish(
      text="Hello",
      segments=[
        @provider.TranscriptionSegment::new(
          text="Hello",
          start_second=0.0,
          end_second=1.0,
        ),
      ],
      language=Some("en"),
      duration_in_seconds=Some(1.0),
      provider_metadata={ "openai": { "requestId": "request-1" } },
    ),
    @provider.TranscriptionV4Raw({ "type": "provider.chunk" }),
    @provider.TranscriptionV4Error(
      @provider.StreamErrorInfo::new("rate limited", data={
        "code": "rate_limit",
      }),
    ),
  ]
  for part in parts {
    let encoded = serializeTranscriptionStreamPart(part).unwrap()
    assert_eq(parse_transcription_stream_part(encoded), Some(part))
  }
}

///|
test "transcription envelope uses ISO timestamps for response metadata" {
  let part = @provider.TranscriptionV4ResponseMetadata(
    @provider.ResponseMetadata::new(
      model_id="openai/gpt-realtime-whisper",
      created_at=1767225600,
      headers={ "x-request-id": "request-1" },
      body="diagnostic",
    ),
  )
  let encoded = serialize_transcription_stream_part(part).unwrap()
  let encoded_json = @json.parse(encoded)
  assert_eq(json_string_field(encoded_json, "type"), Some("response-metadata"))
  assert_eq(
    json_string_field(encoded_json, "timestamp"),
    Some("2026-01-01T00:00:00.000Z"),
  )
  assert_eq(
    json_string_field(encoded_json, "modelId"),
    Some("openai/gpt-realtime-whisper"),
  )
  assert_true(
    encoded_json is { "headers": { "x-request-id": "request-1", .. }, .. },
  )
  assert_eq(json_string_field(encoded_json, "body"), Some("diagnostic"))
  match parseTranscriptionStreamPart(encoded) {
    Some(@provider.TranscriptionV4ResponseMetadata(metadata)) => {
      assert_eq(metadata.created_at, Some(1767225600))
      assert_eq(metadata.model_id, Some("openai/gpt-realtime-whisper"))
      assert_eq(metadata.headers["x-request-id"], "request-1")
      assert_eq(metadata.body, Some("diagnostic"))
    }
    _ => fail("expected response metadata")
  }
}

///|
test "transcription envelope rejects malformed server parts" {
  let invalid = [
    "{not-json", "[]", "{\"type\":\"future-part\"}", "{\"type\":\"stream-start\"}",
    "{\"type\":\"transcript-delta\",\"delta\":42}", "{\"type\":\"transcript-partial\"}",
    "{\"type\":\"transcript-final\",\"text\":\"done\",\"channelIndex\":0.5}", "{\"type\":\"finish\",\"text\":\"done\"}",
    "{\"type\":\"finish\",\"text\":\"done\",\"segments\":[{}]}", "{\"type\":\"response-metadata\",\"timestamp\":\"not-a-date\"}",
    "{\"type\":\"raw\"}", "{\"type\":\"error\"}", "{\"type\":\"transcript-delta\",\"delta\":\"x\",\"__proto__\":{}}",
  ]
  for frame in invalid {
    assert_eq(parse_transcription_stream_part(frame), None)
  }
}

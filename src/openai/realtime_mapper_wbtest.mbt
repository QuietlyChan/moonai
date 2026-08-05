///|
test "OpenAI realtime session config maps audio VAD tools and provider options" {
  let config = @provider.RealtimeSessionConfig::new(
    instructions="Be concise",
    voice="alloy",
    output_modalities=[@provider.RealtimeText, @provider.RealtimeAudio],
    input_audio_format=@provider.AudioFormat::new(
      media_type="audio/pcm",
      sample_rate=24_000,
    ),
    input_audio_transcription=@provider.RealtimeAudioTranscriptionConfig::new(
      model="gpt-4o-mini-transcribe",
      language="en",
      prompt="Short voice messages",
    ),
    output_audio_format=@provider.AudioFormat::new(
      media_type="audio/pcm",
      sample_rate=24_000,
    ),
    turn_detection=@provider.RealtimeTurnDetection::server_vad(
      threshold=0.6,
      silence_duration_ms=500,
      prefix_padding_ms=200,
    ),
    tools=[
      @provider.RealtimeToolDefinition::new(
        name="weather",
        description="Look up weather",
        parameters={
          "type": "object",
          "properties": { "city": { "type": "string" } },
        },
      ),
    ],
    provider_options={ "tracing": { "enabled": true } },
  )
  json_inspect(build_openai_realtime_session_config(config, "gpt-realtime"), content={
    "type": "realtime",
    "model": "gpt-realtime",
    "instructions": "Be concise",
    "output_modalities": ["text", "audio"],
    "audio": {
      "input": {
        "format": { "type": "audio/pcm", "rate": 24000 },
        "turn_detection": {
          "type": "server_vad",
          "threshold": 0.6,
          "silence_duration_ms": 500,
          "prefix_padding_ms": 200,
        },
        "transcription": {
          "model": "gpt-4o-mini-transcribe",
          "language": "en",
          "prompt": "Short voice messages",
        },
      },
      "output": {
        "format": { "type": "audio/pcm", "rate": 24000 },
        "voice": "alloy",
      },
    },
    "tools": [
      {
        "type": "function",
        "name": "weather",
        "description": "Look up weather",
        "parameters": {
          "type": "object",
          "properties": { "city": { "type": "string" } },
        },
      },
    ],
    "tool_choice": "auto",
    "tracing": { "enabled": true },
  })
}

///|
test "OpenAI realtime transcription defaults and disabled VAD match upstream" {
  let config = @provider.RealtimeSessionConfig::new(
    input_audio_transcription=@provider.RealtimeAudioTranscriptionConfig::new(),
    turn_detection=@provider.RealtimeTurnDetection::disabled(),
  )
  json_inspect(build_openai_realtime_session_config(config, "gpt-realtime"), content={
    "type": "realtime",
    "model": "gpt-realtime",
    "audio": {
      "input": {
        "turn_detection": null,
        "transcription": { "model": "gpt-realtime-whisper" },
      },
    },
  })
}

///|
test "OpenAI realtime serializes normalized client events" {
  json_inspect(
    serialize_openai_realtime_client_event(
      @provider.RealtimeInputAudioAppend("AQID"),
      "gpt-realtime",
    ),
    content={ "type": "input_audio_buffer.append", "audio": "AQID" },
  )
  json_inspect(
    serialize_openai_realtime_client_event(
      @provider.RealtimeConversationItemCreate(
        @provider.RealtimeTextMessage(text="hello"),
      ),
      "gpt-realtime",
    ),
    content={
      "type": "conversation.item.create",
      "item": {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "hello" }],
      },
    },
  )
  json_inspect(
    serialize_openai_realtime_client_event(
      @provider.RealtimeConversationItemCreate(
        @provider.RealtimeFunctionCallOutput(
          call_id="call-1",
          name=Some("weather"),
          output="{\"temperature\":20}",
        ),
      ),
      "gpt-realtime",
    ),
    content={
      "type": "conversation.item.create",
      "item": {
        "type": "function_call_output",
        "call_id": "call-1",
        "output": "{\"temperature\":20}",
      },
    },
  )
  json_inspect(
    serialize_openai_realtime_client_event(
      @provider.RealtimeResponseCreate(
        Some(
          @provider.RealtimeResponseCreateOptions::new(
            modalities=["audio"],
            instructions="Answer now",
            metadata={ "requestId": "req-1" },
          ),
        ),
      ),
      "gpt-realtime",
    ),
    content={
      "type": "response.create",
      "response": {
        "output_modalities": ["audio"],
        "instructions": "Answer now",
        "metadata": { "requestId": "req-1" },
      },
    },
  )
}

///|
test "OpenAI realtime parses lifecycle content tool and error events" {
  let session : Json = {
    "type": "session.created",
    "session": { "id": "sess-1" },
  }
  assert_eq(
    parse_openai_realtime_server_event(session),
    @provider.RealtimeSessionCreated(session_id=Some("sess-1"), raw=session),
  )
  let delta : Json = {
    "type": "response.output_text.delta",
    "response_id": "resp-1",
    "item_id": "item-1",
    "delta": "hello",
  }
  assert_eq(
    parse_openai_realtime_server_event(delta),
    @provider.RealtimeTextDelta(
      response_id="resp-1",
      item_id="item-1",
      delta="hello",
      raw=delta,
    ),
  )
  let tool : Json = {
    "type": "response.function_call_arguments.done",
    "response_id": "resp-1",
    "item_id": "item-2",
    "call_id": "call-1",
    "name": "weather",
    "arguments": "{\"city\":\"Paris\"}",
  }
  assert_eq(
    parse_openai_realtime_server_event(tool),
    @provider.RealtimeFunctionCallArgumentsDone(
      response_id="resp-1",
      item_id="item-2",
      call_id="call-1",
      name="weather",
      arguments="{\"city\":\"Paris\"}",
      raw=tool,
    ),
  )
  let error : Json = {
    "type": "error",
    "error": { "message": "bad event", "code": "invalid_event" },
  }
  assert_eq(
    parse_openai_realtime_server_event(error),
    @provider.RealtimeError(
      message="bad event",
      code=Some("invalid_event"),
      raw=error,
    ),
  )
  let custom : Json = { "type": "rate_limits.updated", "remaining": 10 }
  assert_eq(
    parse_openai_realtime_server_event(custom),
    @provider.RealtimeCustom(raw_type="rate_limits.updated", raw=custom),
  )
}

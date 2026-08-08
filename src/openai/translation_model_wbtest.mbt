///|
test "OpenAI translation options preserve the empty provider schema" {
  json_inspect(OpenAITranslationModelOptions::new().to_provider_options(), content={
    "openai": Json::empty_object(),
  })
}

///|
priv struct MockTranslationAudioStream {
  chunks : Array[@provider.AudioChunk]
  index : Ref[Int]
  cancelled : Ref[Bool]
}

///|
fn MockTranslationAudioStream::new(
  chunks : Array[@provider.AudioChunk],
) -> MockTranslationAudioStream {
  { chunks, index: Ref(0), cancelled: Ref(false) }
}

///|
impl @provider.AudioStream for MockTranslationAudioStream with fn read_next(
  self,
) {
  if self.cancelled.val || self.index.val >= self.chunks.length() {
    return None
  }
  let chunk = self.chunks[self.index.val]
  self.index.val = self.index.val + 1
  Some(chunk)
}

///|
impl @provider.AudioStream for MockTranslationAudioStream with fn cancel(self) {
  self.cancelled.val = true
}

///|
priv struct MockTranslationWebSocketConnection {
  sent : Array[String]
  incoming : Array[@provider_utils.WebSocketReceive]
  next_incoming : Ref[Int]
  closed : Ref[Bool]
  expected_sends_before_receive : Int
}

///|
fn MockTranslationWebSocketConnection::new(
  incoming : Array[@provider_utils.WebSocketReceive],
  expected_sends_before_receive? : Int = 3,
) -> MockTranslationWebSocketConnection {
  {
    sent: [],
    incoming,
    next_incoming: Ref(0),
    closed: Ref(false),
    expected_sends_before_receive,
  }
}

///|
impl @provider_utils.WebSocketConnection for MockTranslationWebSocketConnection with fn send_text(
  self,
  text,
) {
  self.sent.push(text)
}

///|
impl @provider_utils.WebSocketConnection for MockTranslationWebSocketConnection with fn send_binary(
  self,
  data,
) {
  self.sent.push("binary:\{@base64.encode(data)}")
}

///|
impl @provider_utils.WebSocketConnection for MockTranslationWebSocketConnection with fn receive(
  self,
) {
  while self.sent.length() < self.expected_sends_before_receive &&
        !self.closed.val {
    @async.pause()
  }
  while self.next_incoming.val >= self.incoming.length() && !self.closed.val {
    @async.pause()
  }
  if self.closed.val {
    return @provider_utils.WebSocketClosed(
      code=Some(1000),
      reason=Some("client closed"),
    )
  }
  let message = self.incoming[self.next_incoming.val]
  self.next_incoming.val = self.next_incoming.val + 1
  message
}

///|
impl @provider_utils.WebSocketConnection for MockTranslationWebSocketConnection with fn send_close(
  self,
  code,
  reason,
) {
  let suffix = reason.unwrap_or("")
  self.sent.push("close:\{code}:\{suffix}")
  self.closed.val = true
}

///|
impl @provider_utils.WebSocketConnection for MockTranslationWebSocketConnection with fn close(
  self,
) {
  self.closed.val = true
}

///|
priv struct MockTranslationWebSocketConnector {
  connection : MockTranslationWebSocketConnection
  urls : Array[String]
  protocols : Array[Array[String]]
  headers : Array[Map[String, String]]
  failure : String?
}

///|
fn MockTranslationWebSocketConnector::new(
  connection : MockTranslationWebSocketConnection,
  failure? : String,
) -> MockTranslationWebSocketConnector {
  { connection, urls: [], protocols: [], headers: [], failure }
}

///|
impl @provider_utils.WebSocketConnector for MockTranslationWebSocketConnector with fn connect(
  self,
  url,
  protocols,
  headers,
) {
  self.urls.push(url)
  self.protocols.push(protocols.copy())
  self.headers.push(@provider_utils.copy_headers(headers))
  match self.failure {
    Some(message) => fail(message)
    None => self.connection as &@provider_utils.WebSocketConnection
  }
}

///|
fn translation_text_message(value : Json) -> @provider_utils.WebSocketReceive {
  @provider_utils.WebSocketText(value.stringify())
}

///|
async test "OpenAI translation streams realtime audio and transcripts" {
  let connection = MockTranslationWebSocketConnection::new([
    translation_text_message({
      "type": "session.input_transcript.delta",
      "delta": "Hello ",
    }),
    translation_text_message({
      "type": "session.input_transcript.delta",
      "delta": "world",
    }),
    translation_text_message({
      "type": "session.output_transcript.delta",
      "delta": "Hola ",
    }),
    translation_text_message({
      "type": "session.output_transcript.delta",
      "delta": "mundo",
    }),
    translation_text_message({
      "type": "session.output_audio.delta",
      "delta": "BAUG",
    }),
    translation_text_message({ "type": "session.closed" }),
  ])
  let connector = MockTranslationWebSocketConnector::new(connection)
  let provider = create_openai(
    api_key="test-api-key",
    headers={ "Custom-Header": "custom-value" },
    websocket_connector=connector,
  )
  let model = provider.translation("gpt-realtime-translate")
  assert_eq(model.provider(), "openai.translation")
  assert_eq(model.model_id(), "gpt-realtime-translate")
  let audio = MockTranslationAudioStream::new([
    @provider.AudioChunk::bytes(b"\x01\x02\x03"),
  ])
  let events : Array[@provider.SpeechTranslationStreamEvent] = []
  let result = @ai.stream_speech_translation(
    model,
    audio~,
    input_audio_format=@provider.AudioFormat::new(
      media_type="audio/pcm",
      sample_rate=24_000,
    ),
    target_language="es",
    on_event=event => events.push(event),
  )
  assert_eq(result.source_text, "Hello world")
  assert_eq(result.output_text, "Hola mundo")
  assert_eq(result.response.unwrap().model_id, Some("gpt-realtime-translate"))
  assert_true(result.response.unwrap().created_at is Some(_))
  assert_true(audio.cancelled.val)
  assert_eq(connector.urls, [
    "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate",
  ])
  assert_eq(connector.protocols, [
    ["realtime", "openai-insecure-api-key.test-api-key"],
  ])
  assert_eq(connector.headers[0].get("Authorization"), None)
  assert_eq(connector.headers[0].get("authorization"), None)
  assert_eq(connector.headers[0].get("Custom-Header"), Some("custom-value"))
  assert_eq(connection.sent.length(), 3)
  json_inspect(@json.parse(connection.sent[0]), content={
    "type": "session.update",
    "session": {
      "audio": {
        "input": {
          "transcription": { "model": "gpt-realtime-whisper" },
          "noise_reduction": null,
        },
        "output": { "language": "es" },
      },
    },
  })
  json_inspect(@json.parse(connection.sent[1]), content={
    "type": "session.input_audio_buffer.append",
    "audio": "AQID",
  })
  json_inspect(@json.parse(connection.sent[2]), content={
    "type": "session.close",
  })
  assert_eq(events, [
    @provider.SpeechTranslationStreamStart(warnings=[]),
    @provider.SpeechTranslationSourceTranscriptDelta(
      id=None,
      delta="Hello ",
      provider_metadata=Map([]),
    ),
    @provider.SpeechTranslationSourceTranscriptDelta(
      id=None,
      delta="world",
      provider_metadata=Map([]),
    ),
    @provider.SpeechTranslationOutputTextDelta(
      id=None,
      delta="Hola ",
      provider_metadata=Map([]),
    ),
    @provider.SpeechTranslationOutputTextDelta(
      id=None,
      delta="mundo",
      provider_metadata=Map([]),
    ),
    @provider.SpeechTranslationAudio(
      id=None,
      audio=@provider.SpeechAudioData::base64("BAUG"),
      provider_metadata=Map([]),
    ),
    @provider.SpeechTranslationSourceTranscriptFinal(
      id=None,
      text="Hello world",
      start_second=None,
      end_second=None,
      channel_index=None,
      provider_metadata=Map([]),
    ),
    @provider.SpeechTranslationOutputTextFinal(
      id=None,
      text="Hola mundo",
      provider_metadata=Map([]),
    ),
    @provider.SpeechTranslationFinish(
      source_text="Hello world",
      output_text="Hola mundo",
      duration_seconds=None,
      usage=None,
      provider_metadata=Map([]),
    ),
  ])
}

///|
async test "OpenAI translation emits warnings raw chunks and recoverable errors" {
  let raw_error : Json = {
    "type": "error",
    "error": { "message": "invalid target language" },
  }
  let connection = MockTranslationWebSocketConnection::new([
    translation_text_message({ "type": "session.updated" }),
    translation_text_message(raw_error),
    translation_text_message({
      "type": "session.output_audio.delta",
      "delta": "",
    }),
    translation_text_message({
      "type": "session.output_transcript.delta",
      "delta": "Hola",
    }),
    translation_text_message({ "type": "session.closed" }),
  ])
  let connector = MockTranslationWebSocketConnector::new(connection)
  let provider = create_openai(
    api_key="test-api-key",
    websocket_connector=connector,
  )
  let audio = MockTranslationAudioStream::new([
    @provider.AudioChunk::base64("AQID"),
  ])
  let events : Array[@provider.SpeechTranslationStreamEvent] = []
  let result = @ai.stream_speech_translation(
    provider.speech_translation_model("gpt-realtime-translate"),
    audio~,
    input_audio_format=@provider.AudioFormat::new(media_type="audio/pcm"),
    target_language="es",
    source_language="en",
    output_audio_format=@provider.AudioFormat::new(
      media_type="audio/pcm",
      sample_rate=24_000,
    ),
    include_raw_chunks=true,
    on_event=event => events.push(event),
  )
  assert_eq(result.output_text, "Hola")
  assert_eq(result.warnings, [
    @provider.Warning::Unsupported(
      feature="sourceLanguage",
      details="The OpenAI Realtime translation API auto-detects the source language and does not accept a source language.",
    ),
    @provider.Warning::Unsupported(
      feature="outputAudioFormat",
      details="The OpenAI Realtime translation API always outputs 24kHz 16-bit PCM audio and does not accept an output audio format.",
    ),
  ])
  let mut raw_count = 0
  let mut audio_count = 0
  let mut saw_error = false
  for event in events {
    match event {
      @provider.SpeechTranslationRaw(_) => raw_count = raw_count + 1
      @provider.SpeechTranslationAudio(..) => audio_count = audio_count + 1
      @provider.SpeechTranslationStreamError(message) =>
        saw_error = message == "invalid target language"
      _ => ()
    }
  }
  assert_eq(raw_count, 5)
  assert_eq(audio_count, 0)
  assert_true(saw_error)
}

///|
async test "OpenAI translation validates PCM format before connecting" {
  let connection = MockTranslationWebSocketConnection::new([])
  let connector = MockTranslationWebSocketConnector::new(connection)
  let provider = create_openai(
    api_key="test-api-key",
    websocket_connector=connector,
  )
  let audio = MockTranslationAudioStream::new([])
  try
    @ai.stream_speech_translation(
      provider.translation("gpt-realtime-translate"),
      audio~,
      input_audio_format=@provider.AudioFormat::new(
        media_type="audio/pcmu",
        sample_rate=24_000,
      ),
      target_language="es",
    )
  catch {
    error =>
      assert_true(
        "\{error}".contains("only supports 24kHz 16-bit PCM input audio"),
      )
  } noraise {
    _ => fail("expected unsupported input audio format")
  }
  assert_eq(connector.urls, [])
}

///|
async test "OpenAI translation reports unexpected WebSocket close diagnostics" {
  let connection = MockTranslationWebSocketConnection::new([
    @provider_utils.WebSocketClosed(
      code=Some(1011),
      reason=Some("internal server error"),
    ),
  ])
  let connector = MockTranslationWebSocketConnector::new(connection)
  let provider = create_openai(
    api_key="test-api-key",
    websocket_connector=connector,
  )
  let audio = MockTranslationAudioStream::new([
    @provider.AudioChunk::bytes(b"\x01"),
  ])
  try
    @ai.stream_speech_translation(
      provider.translation("gpt-realtime-translate"),
      audio~,
      input_audio_format=@provider.AudioFormat::new(media_type="audio/pcm"),
      target_language="es",
    )
  catch {
    error =>
      assert_true(
        "\{error}".contains(
          "closed unexpectedly before finishing (code 1011, reason: internal server error)",
        ),
      )
  } noraise {
    _ => fail("expected unexpected close error")
  }
  assert_true(audio.cancelled.val)
}

///|
async test "OpenAI translation cancels audio when WebSocket connection fails" {
  let connection = MockTranslationWebSocketConnection::new([])
  let connector = MockTranslationWebSocketConnector::new(
    connection,
    failure="constructor failed",
  )
  let provider = create_openai(
    api_key="test-api-key",
    websocket_connector=connector,
  )
  let audio = MockTranslationAudioStream::new([])
  try
    @ai.stream_speech_translation(
      provider.translation("gpt-realtime-translate"),
      audio~,
      input_audio_format=@provider.AudioFormat::new(media_type="audio/pcm"),
      target_language="es",
    )
  catch {
    error => assert_true("\{error}".contains("constructor failed"))
  } noraise {
    _ => fail("expected connector failure")
  }
  assert_true(audio.cancelled.val)
}

///|
async test "OpenAI translation observes cancellation during a live session" {
  @async.with_task_group() <| group => {
    let connection = MockTranslationWebSocketConnection::new(
      [],
      expected_sends_before_receive=0,
    )
    let connector = MockTranslationWebSocketConnector::new(connection)
    let provider = create_openai(
      api_key="test-api-key",
      websocket_connector=connector,
    )
    let audio = MockTranslationAudioStream::new([])
    let token = @provider.CancellationToken::new()
    group.spawn_bg(no_wait=true) <| () => {
      @async.sleep(5)
      token.cancel()
    }
    try
      @ai.stream_speech_translation(
        provider.translation("gpt-realtime-translate"),
        audio~,
        input_audio_format=@provider.AudioFormat::new(media_type="audio/pcm"),
        target_language="es",
        cancellation_token=token,
      )
    catch {
      @provider.CancellationError => ()
      error => fail("unexpected cancellation error: \{error}")
    } noraise {
      _ => fail("expected cancellation")
    }
    assert_true(connection.closed.val)
    assert_true(audio.cancelled.val)
  }
}

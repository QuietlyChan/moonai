///|
priv struct MockTranscriptionAudioStream {
  chunks : Array[@provider.AudioChunk]
  index : Ref[Int]
  cancelled : Ref[Bool]
}

///|
fn MockTranscriptionAudioStream::new(
  chunks : Array[@provider.AudioChunk],
) -> MockTranscriptionAudioStream {
  { chunks, index: Ref(0), cancelled: Ref(false) }
}

///|
impl @provider.AudioStream for MockTranscriptionAudioStream with fn read_next(
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
impl @provider.AudioStream for MockTranscriptionAudioStream with fn cancel(self) {
  self.cancelled.val = true
}

///|
priv struct MockTranscriptionWebSocketConnection {
  sent : Array[String]
  incoming : Array[@provider_utils.WebSocketReceive]
  next_incoming : Ref[Int]
  closed : Ref[Bool]
  expected_sends_before_receive : Int
}

///|
fn MockTranscriptionWebSocketConnection::new(
  incoming : Array[@provider_utils.WebSocketReceive],
  expected_sends_before_receive? : Int = 3,
) -> MockTranscriptionWebSocketConnection {
  {
    sent: [],
    incoming,
    next_incoming: Ref(0),
    closed: Ref(false),
    expected_sends_before_receive,
  }
}

///|
impl @provider_utils.WebSocketConnection for MockTranscriptionWebSocketConnection with fn send_text(
  self,
  text,
) {
  self.sent.push(text)
}

///|
impl @provider_utils.WebSocketConnection for MockTranscriptionWebSocketConnection with fn send_binary(
  self,
  data,
) {
  self.sent.push("binary:\{@base64.encode(data)}")
}

///|
impl @provider_utils.WebSocketConnection for MockTranscriptionWebSocketConnection with fn receive(
  self,
) {
  while self.sent.length() < self.expected_sends_before_receive &&
        !self.closed.val {
    @async.pause()
  }
  if self.next_incoming.val >= self.incoming.length() {
    return @provider_utils.WebSocketClosed(
      code=Some(1000),
      reason=Some("mock input exhausted"),
    )
  }
  let message = self.incoming[self.next_incoming.val]
  self.next_incoming.val = self.next_incoming.val + 1
  message
}

///|
impl @provider_utils.WebSocketConnection for MockTranscriptionWebSocketConnection with fn send_close(
  self,
  code,
  reason,
) {
  self.sent.push("close:\{code}:\{reason.unwrap_or("")}")
  self.closed.val = true
}

///|
impl @provider_utils.WebSocketConnection for MockTranscriptionWebSocketConnection with fn close(
  self,
) {
  self.closed.val = true
}

///|
priv struct MockTranscriptionWebSocketConnector {
  connection : MockTranscriptionWebSocketConnection
  urls : Array[String]
  protocols : Array[Array[String]]
  headers : Array[Map[String, String]]
}

///|
fn MockTranscriptionWebSocketConnector::new(
  connection : MockTranscriptionWebSocketConnection,
) -> MockTranscriptionWebSocketConnector {
  { connection, urls: [], protocols: [], headers: [] }
}

///|
impl @provider_utils.WebSocketConnector for MockTranscriptionWebSocketConnector with fn connect(
  self,
  url,
  protocols,
  headers,
) {
  self.urls.push(url)
  self.protocols.push(protocols.copy())
  self.headers.push(@provider_utils.copy_headers(headers))
  self.connection as &@provider_utils.WebSocketConnection
}

///|
fn transcription_text_message(value : Json) -> @provider_utils.WebSocketReceive {
  @provider_utils.WebSocketText(value.stringify())
}

///|
async test "OpenAI realtime transcription streams normalized events" {
  let connection = MockTranscriptionWebSocketConnection::new([
    transcription_text_message({
      "type": "conversation.item.input_audio_transcription.delta",
      "item_id": "item-1",
      "delta": "hello ",
    }),
    transcription_text_message({
      "type": "conversation.item.input_audio_transcription.completed",
      "item_id": "item-1",
      "transcript": "hello world",
    }),
  ])
  let connector = MockTranscriptionWebSocketConnector::new(connection)
  let model = create_openai(
    api_key="test-api-key",
    headers={ "Custom-Header": "custom-value" },
    websocket_connector=connector,
  ).transcription("gpt-realtime-whisper")
  let audio = MockTranscriptionAudioStream::new([
    @provider.AudioChunk::bytes(b"\x01\x02\x03"),
  ])
  let events : Array[@provider.TranscriptionStreamEvent] = []
  let result = @ai.stream_transcribe(
    model,
    audio~,
    input_audio_format=@provider.AudioFormat::new(
      media_type="audio/pcm",
      sample_rate=24_000,
    ),
    provider_options=OpenAITranscriptionModelOptions::new(
      language="en",
      prompt="REST-only prompt",
      streaming=OpenAITranscriptionStreamingOptions::new(
        delay=OpenAITranscriptionDelayLow,
        include_values=["item.input_audio_transcription.logprobs"],
      ),
    ).to_provider_options(),
    include_raw_chunks=true,
    on_event=event => events.push(event),
  )
  assert_eq(result.text, "hello world")
  assert_eq(result.language, Some("en"))
  assert_eq(result.response.unwrap().model_id, Some("gpt-realtime-whisper"))
  assert_eq(result.warnings.length(), 1)
  assert_true(audio.cancelled.val)
  assert_eq(connector.urls, [
    "wss://api.openai.com/v1/realtime?intent=transcription",
  ])
  assert_eq(connector.protocols, [
    ["realtime", "openai-insecure-api-key.test-api-key"],
  ])
  assert_eq(connector.headers[0].get("Authorization"), None)
  assert_eq(connector.headers[0].get("Custom-Header"), Some("custom-value"))
  assert_eq(connection.sent.length(), 4)
  json_inspect(@json.parse(connection.sent[0]), content={
    "type": "session.update",
    "session": {
      "type": "transcription",
      "audio": {
        "input": {
          "format": { "type": "audio/pcm", "rate": 24000 },
          "transcription": {
            "model": "gpt-realtime-whisper",
            "language": "en",
            "delay": "low",
          },
          "turn_detection": null,
        },
      },
      "include": ["item.input_audio_transcription.logprobs"],
    },
  })
  json_inspect(@json.parse(connection.sent[1]), content={
    "type": "input_audio_buffer.append",
    "audio": "AQID",
  })
  json_inspect(@json.parse(connection.sent[2]), content={
    "type": "input_audio_buffer.commit",
  })
  assert_eq(connection.sent[3], "close:1000:")
  assert_eq(events.length(), 6)
  match events[0] {
    @provider.TranscriptionStreamStart(warnings~) => {
      assert_eq(warnings.length(), 1)
      assert_true(
        warnings[0]
        is @provider.Warning::Unsupported(
          feature="providerOptions.openai.prompt",
          details=_
        ),
      )
    }
    _ => fail("expected a transcription stream start")
  }
  assert_true(events[1] is @provider.TranscriptionRaw(_))
  assert_true(
    events[2]
    is @provider.TranscriptionDelta(
      id=Some("item-1"),
      delta="hello ",
      provider_metadata=_
    ),
  )
  assert_true(events[3] is @provider.TranscriptionRaw(_))
  assert_true(
    events[4]
    is @provider.TranscriptionFinal(id=Some("item-1"), text="hello world", ..),
  )
  assert_true(
    events[5]
    is @provider.TranscriptionFinish(
      text="hello world",
      language=Some("en"),
      ..
    ),
  )
}

///|
async test "OpenAI rejects streaming on a buffered transcription model" {
  let model = openai_transcription("whisper-1", api_key="test-api-key")
  let audio = @provider.audio_chunks([])
  try
    @ai.stream_transcribe(
      model,
      audio~,
      input_audio_format=@provider.AudioFormat::new(media_type="audio/pcm"),
    )
  catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_true(functionality.contains("streaming transcription"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an unsupported streaming transcription error")
  }
}

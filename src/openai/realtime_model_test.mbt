///|
async test "OpenAI realtime creates client secrets and factory tokens" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let bodies : Array[Json] = []
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/realtime/client_secrets")
          assert_eq(
            request.headers.get("authorization"),
            Some("Bearer test-key"),
          )
          assert_eq(
            request.headers.get("openai-organization"),
            Some("org-test"),
          )
          assert_eq(
            request.headers.get("content-type"),
            Some("application/json"),
          )
          bodies.push(@json.parse(body.read_all().text()))
          let index = bodies.length()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            (
              { "value": "secret-\{index}", "expires_at": 1700000000 + index } :
              Json).stringify(),
          )
        },
        max_connections=2,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      organization="org-test",
      idle_timeout_ms=2_000,
    )
    let model = provider.realtime("gpt-realtime")
    assert_eq(model.provider(), "openai.realtime")
    assert_eq(model.model_id(), "gpt-realtime")
    let direct = @ai.create_realtime_client_secret(model)
    assert_eq(direct.token, "secret-1")
    assert_eq(direct.expires_at, Some(1700000001))
    assert_eq(
      direct.url,
      "wss://127.0.0.1:\{server.addr.port()}/v1/realtime?model=gpt-realtime",
    )
    let factory = provider.experimental_realtime()
    let generic_factory = factory as &@provider.RealtimeFactoryV4
    assert_eq(generic_factory.provider(), "openai")
    let generic_model = generic_factory.model("gpt-realtime-generic")
    assert_eq(generic_model.specification_version(), "v4")
    assert_eq(generic_model.provider(), "openai.realtime")
    assert_eq(generic_model.model_id(), "gpt-realtime-generic")
    let from_factory = factory.getToken(
      @provider.RealtimeFactoryTokenOptions::new(
        model="gpt-realtime-preview",
        expires_after_seconds=60,
        session_config=@provider.RealtimeSessionConfig::new(
          instructions="Be concise",
          input_audio_transcription=@provider.RealtimeAudioTranscriptionConfig::new(),
        ),
      ),
    )
    assert_eq(from_factory.token, "secret-2")
    assert_eq(
      from_factory.url,
      "wss://127.0.0.1:\{server.addr.port()}/v1/realtime?model=gpt-realtime-preview",
    )
    assert_eq(bodies.length(), 2)
    json_inspect(bodies[0], content={
      "session": { "type": "realtime", "model": "gpt-realtime" },
    })
    json_inspect(bodies[1], content={
      "session": {
        "type": "realtime",
        "model": "gpt-realtime-preview",
        "instructions": "Be concise",
        "audio": {
          "input": { "transcription": { "model": "gpt-realtime-whisper" } },
        },
      },
      "expires_after": { "anchor": "created_at", "seconds": 60 },
    })
    let websocket = model.get_websocket_config(direct.token, direct.url)
    assert_eq(
      websocket,
      @provider.RealtimeWebSocketConfig::new(url=direct.url, protocols=[
        "realtime", "openai-insecure-api-key.secret-1",
      ]),
    )
  }
}

///|
test "OpenAI realtime model delegates client and server event mapping" {
  let model = openai_realtime("gpt-realtime", api_key="test-key")
  json_inspect(
    model.serialize_client_event(@provider.RealtimeInputAudioCommit),
    content={ "type": "input_audio_buffer.commit" },
  )
  let raw : Json = {
    "type": "response.output_audio.delta",
    "response_id": "resp-1",
    "item_id": "item-1",
    "delta": "AQID",
  }
  assert_eq(model.parse_server_event(raw), [
    @provider.RealtimeAudioDelta(
      response_id="resp-1",
      item_id="item-1",
      delta="AQID",
      raw~,
    ),
  ])
}

///|
async test "OpenAI realtime rejects client secret responses without a token" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write("{\"expires_at\":1700000000}")
        },
        max_connections=1,
      )
    }
    let model = openai_realtime(
      "gpt-realtime",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    try @ai.create_realtime_client_secret(model) catch {
      @provider.APICallError(
        message~,
        status_code~,
        is_retryable~,
        data~,
        cause~,
        ..
      ) => {
        assert_eq(message, "Failed to process successful response")
        assert_eq(status_code, Some(200))
        assert_false(is_retryable)
        assert_eq(data, Some(({ "expires_at": 1700000000 } : Json)))
        assert_true(cause.unwrap_or("").contains("response is missing value"))
      }
      error => fail("unexpected realtime client secret error: \{error}")
    } noraise {
      _ => fail("expected missing realtime token error")
    }
  }
}

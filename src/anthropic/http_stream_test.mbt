///|
async fn bind_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
async test "streamText drives an Anthropic Messages SSE request" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/messages")
          assert_true(request.headers.get("x-api-key") is Some("test-key"))
          assert_true(
            request.headers.get("anthropic-version") is Some("2023-06-01"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"model\":\"test-model\""))
          assert_true(request_body.contains("\"stream\":true"))
          assert_true(request_body.contains("\"max_tokens\":4096"))
          assert_true(request_body.contains("\"temperature\":1"))
          assert_false(request_body.contains("output_config"))
          assert_false(request_body.contains("frequency_penalty"))
          assert_false(request_body.contains("presence_penalty"))
          assert_false(request_body.contains("\"seed\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_test\",\"model\":\"test-model\",\"provider_metadata\":{\"anthropic.messages\":{\"trace_id\":\"a-1\"}},\"usage\":{\"input_tokens\":2}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello Anthropic\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
          )
          connection.write(
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":3}}\n\n",
          )
          connection.write("data: {\"type\":\"message_stop\"}\n\n")
        },
        max_connections=1,
      )
    }
    let model = @anthropic.anthropic(
      "test-model",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let deltas : Array[String] = []
    let response = @moonai.streamText(
      model,
      prompt="hello",
      frequency_penalty=0.2,
      presence_penalty=0.3,
      seed=7,
      temperature=1.5,
      response_format=@moonai.JsonObject,
      on_event=event => {
        match event {
          @moonai.TextDelta(delta~, ..) => deltas.push(delta)
          _ => ()
        }
      },
    )
    assert_eq(deltas, ["Hello Anthropic"])
    assert_eq(response.text, "Hello Anthropic")
    assert_eq(response.finish_reason, @moonai.Stop)
    assert_eq(response.usage.total_tokens, 5)
    match response.response {
      Some(metadata) => {
        assert_eq(metadata.status_code, Some(200))
        assert_eq(metadata.id, Some("msg_test"))
        assert_eq(metadata.model_id, Some("test-model"))
      }
      None => fail("expected streaming response metadata")
    }
    json_inspect(response.provider_metadata["anthropic.messages"], content={
      "trace_id": "a-1",
    })
    assert_eq(response.warnings, [
      @moonai.Warning::Unsupported(
        feature="frequencyPenalty",
        details="Anthropic Messages does not define a frequency penalty field.",
      ),
      @moonai.Warning::Unsupported(
        feature="presencePenalty",
        details="Anthropic Messages does not define a presence penalty field.",
      ),
      @moonai.Warning::Unsupported(
        feature="seed",
        details="Anthropic Messages does not define a seed field.",
      ),
      @moonai.Warning::Unsupported(
        feature="temperature",
        details="temperature exceeds Anthropic maximum of 1.0 and is clamped to 1.0.",
      ),
      @moonai.Warning::Unsupported(
        feature="responseFormat",
        details="Anthropic JSON response format requires an explicit schema and is ignored.",
      ),
    ])
  }
}

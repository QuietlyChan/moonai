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
    let model = AnthropicLanguageModelV4::new(
        @anthropic.anthropic_messages(
          "test-model",
          api_key="test-key",
          base_url="http://127.0.0.1:\{server.addr.port()}/v1",
          idle_timeout_ms=2_000,
        ),
      )
      as &@provider.LanguageModelV4
    let deltas : Array[String] = []
    let response = @ai.streamText(
      model,
      prompt="hello",
      frequency_penalty=0.2,
      presence_penalty=0.3,
      seed=7,
      temperature=1.5,
      response_format=@provider.ResponseFormat::json(),
      on_event=event => {
        match event {
          @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
          _ => ()
        }
      },
    )
    assert_eq(deltas, ["Hello Anthropic"])
    assert_eq(deltas.join(""), "Hello Anthropic")
    assert_eq(response.finish_reason.unified, @provider.V4FinishStop)
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(3))
    match response.response {
      Some(metadata) => {
        assert_eq(metadata.status_code, Some(200))
        assert_eq(metadata.id, Some("msg_test"))
        assert_eq(metadata.model_id, Some("test-model"))
      }
      None => fail("expected streaming response metadata")
    }
    json_inspect(response.provider_metadata["anthropic.messages"], content={
      "usage": { "input_tokens": 2, "output_tokens": 3 },
      "trace_id": "a-1",
    })
    assert_eq(response.warnings, [
      @provider.Warning::Unsupported(
        feature="frequencyPenalty",
        details="Anthropic Messages does not define a frequency penalty field.",
      ),
      @provider.Warning::Unsupported(
        feature="presencePenalty",
        details="Anthropic Messages does not define a presence penalty field.",
      ),
      @provider.Warning::Unsupported(
        feature="seed",
        details="Anthropic Messages does not define a seed field.",
      ),
      @provider.Warning::Unsupported(
        feature="temperature",
        details="temperature exceeds Anthropic maximum of 1.0 and is clamped to 1.0.",
      ),
      @provider.Warning::Unsupported(
        feature="responseFormat",
        details="Anthropic JSON response format requires an explicit schema and is ignored.",
      ),
      @provider.Warning::Compatibility(
        feature="maxOutputTokens",
        details="The model 'test-model' is unknown; max output tokens defaulted to 4096.",
      ),
    ])
  }
}

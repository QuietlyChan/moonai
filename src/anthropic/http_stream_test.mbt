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
    match response.provider_metadata["anthropic.messages"] {
      {
        "usage": {
          "input_tokens": Number(input_tokens, ..),
          "output_tokens": Number(output_tokens, ..),
          ..
        },
        "trace_id": String(trace_id),
        ..
      } => {
        assert_eq(input_tokens.to_int(), 2)
        assert_eq(output_tokens.to_int(), 3)
        assert_eq(trace_id, "a-1")
      }
      _ => fail("expected qualified Anthropic stream metadata")
    }
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
        details="1.5 exceeds anthropic maximum of 1.0. clamped to 1.0",
      ),
      @provider.Warning::Unsupported(
        feature="responseFormat",
        details="JSON response format requires a schema. The response format is ignored.",
      ),
      @provider.Warning::Compatibility(
        feature="maxOutputTokens",
        details="The model \"test-model\" is unknown. The max output tokens have been limited to 4096. Set maxOutputTokens explicitly to override this limit.",
      ),
    ])
  }
}

///|
async test "Anthropic request URL builder receives the streaming flag" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/alternate/stream-messages")
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-url-stream\",\"model\":\"test-model\",\"usage\":{\"input_tokens\":1}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"ok\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
          )
          connection.write(
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":1}}\n\n",
          )
          connection.write("data: {\"type\":\"message_stop\"}\n\n")
        },
        max_connections=1,
      )
    }
    let mut saw_streaming = false
    let model = @anthropic.anthropic(
      "test-model",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
      build_request_url=(base_url, is_streaming) => {
        saw_streaming = is_streaming
        @provider_utils.append_path(base_url, "/alternate/stream-messages")
      },
    )
    let mut text = ""
    let response = @ai.streamText(model, prompt="hello", on_event=event => {
      match event {
        @provider.V4TextDelta(delta~, ..) => text = text + delta
        _ => ()
      }
    })
    assert_eq(text, "ok")
    assert_true(saw_streaming)
    assert_eq(response.finish_reason.unified, @provider.V4FinishStop)
  }
}

///|
async test "Anthropic maps an initial overloaded SSE error to a retryable 529" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
            "X-Request-Id": "overloaded-1",
          })
          connection.write(
            "data: {\"type\":\"error\",\"error\":{\"details\":null,\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n",
          )
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
    let events : Array[@provider.LanguageModelV4StreamPart] = []
    try
      @ai.streamText(
        model,
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
        on_event=event => events.push(event),
      )
    catch {
      @provider.APICallError(
        message="Overloaded",
        status_code=Some(529),
        response_headers~,
        response_body~,
        is_retryable=true,
        ..
      ) => {
        assert_eq(response_headers["x-request-id"], "overloaded-1")
        assert_true(response_body.contains("overloaded_error"))
      }
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a retryable Anthropic overload error")
    }
    assert_eq(events.length(), 0)
  }
}

///|
async test "generateText uses the non-streaming Anthropic Messages endpoint" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/messages")
          assert_true(
            request.headers.get("anthropic-beta")
            is Some("configured-beta,custom-beta"),
          )
          let request_body = body.read_all().text()
          assert_false(request_body.contains("\"stream\""))
          assert_true(request_body.contains("\"model\":\"claude-sonnet-4-6\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"type\":\"message\",\"id\":\"msg_1\",\"model\":\"claude-sonnet-4-6\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"brief\",\"signature\":\"sig\"},{\"type\":\"text\",\"text\":\"done\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":2,\"output_tokens\":3}}",
          )
        },
        max_connections=1,
      )
    }
    let model = create_anthropic(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      beta_features=["configured-beta"],
      idle_timeout_ms=2_000,
    ).messages("claude-sonnet-4-6")
    let response = @ai.generate_text(model, prompt="hello", provider_options={
      "anthropic": { "anthropicBeta": ["custom-beta"] },
    })
    assert_eq(response.text(), "done")
    assert_eq(response.reasoning(), "brief")
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(3))
  }
}

///|
async test "Anthropic request URL builder receives the non-streaming flag" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/alternate/messages")
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"type\":\"message\",\"id\":\"msg-url-builder\",\"model\":\"test-model\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
          )
        },
        max_connections=1,
      )
    }
    let mut saw_non_streaming = false
    let model = create_anthropic(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
      build_request_url=(base_url, is_streaming) => {
        saw_non_streaming = !is_streaming
        @provider_utils.append_path(base_url, "/alternate/messages")
      },
    ).messages("test-model")
    let response = @ai.generate_text(model, prompt="hello")
    assert_eq(response.text(), "ok")
    assert_true(saw_non_streaming)
  }
}

///|
async test "Anthropic generate rejects a schema-invalid successful response" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
            "x-request-id": "req-invalid",
          })
          connection.write(
            "{\"id\":\"msg-invalid\",\"content\":[{\"type\":\"text\",\"text\":\"not valid without a message type\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
          )
        },
        max_connections=1,
      )
    }
    let model = create_anthropic(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    ).messages("claude-sonnet-4-6")
    try @ai.generate_text(model, prompt="hello") catch {
      @provider.APICallError(
        message~,
        url~,
        request_body~,
        status_code~,
        response_headers~,
        response_body~,
        is_retryable~,
        data~,
        cause~,
        ..
      ) => {
        assert_eq(message, "Invalid JSON response")
        assert_true(url.has_suffix("/v1/messages"))
        assert_true(request_body.contains("\"model\":\"claude-sonnet-4-6\""))
        assert_eq(status_code, Some(200))
        assert_eq(response_headers.get("x-request-id"), Some("req-invalid"))
        assert_true(response_body.contains("\"id\":\"msg-invalid\""))
        assert_false(is_retryable)
        assert_true(data is Some({ "id": "msg-invalid", .. }))
        assert_true(cause.unwrap_or("").contains("$.type"))
      }
      error => fail("unexpected Anthropic response error: \{error}")
    } noraise {
      _ => fail("expected Anthropic response schema validation to fail")
    }
  }
}

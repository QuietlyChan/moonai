///|
async fn bind_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
async test "streamText drives an OpenAI-compatible HTTP SSE request" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/chat/completions")
          assert_true(
            request.headers.get("authorization") is Some("Bearer test-key"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"model\":\"test-model\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"id\":\"stream-1\",\"model\":\"test-model\",\"created\":1700000001,\"provider_metadata\":{\"local-test.chat\":{\"stream_trace\":\"s-1\"}},\"choices\":[{\"delta\":{\"content\":\"Hello compatible\"},\"finish_reason\":\"stop\"}]}\n\n",
          )
          connection.write(
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":2,\"total_tokens\":4}}\n\n",
          )
        },
        max_connections=1,
      )
    }
    let model = openai_compatible(
      provider_name="local-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let response = @moonai.stream_text(model, prompt="hello")
    assert_eq(response.text, "Hello compatible")
    assert_eq(response.finish_reason, @moonai.Stop)
    assert_eq(response.usage.total_tokens, 4)
    match response.response {
      Some(metadata) => {
        assert_eq(metadata.status_code, Some(200))
        assert_eq(metadata.id, Some("stream-1"))
        assert_eq(metadata.model_id, Some("test-model"))
        assert_eq(metadata.created_at, Some(1700000001))
      }
      None => fail("expected streaming response metadata")
    }
    json_inspect(response.provider_metadata["local-test.chat"], content={
      "stream_trace": "s-1",
    })
  }
}

///|
async test "generateText drives an OpenAI-compatible JSON request" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/chat/completions")
          assert_true(
            request.headers.get("x-request-id") is Some("chat-generate"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"model\":\"test-model\""))
          assert_false(request_body.contains("\"stream\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"chat-1\",\"model\":\"test-model\",\"created\":1700000000,\"provider_metadata\":{\"local-test.chat\":{\"trace_id\":\"trace-1\"}},\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Hello generate\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":2,\"total_tokens\":4}}",
          )
        },
        max_connections=1,
      )
    }
    let model = openai_compatible(
      provider_name="local-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let response = @moonai.generate_text(model, prompt="hello", headers={
      "X-Request-Id": "chat-generate",
    })
    assert_eq(response.text, "Hello generate")
    assert_eq(response.finish_reason, @moonai.Stop)
    assert_eq(response.usage.total_tokens, 4)
    match response.request {
      Some(request) => {
        assert_true(request.url.contains("/v1/chat/completions"))
        assert_false(request.body.contains("\"stream\""))
        assert_eq(request.headers["X-Request-Id"], "chat-generate")
      }
      None => fail("expected request metadata")
    }
    match response.response {
      Some(metadata) => {
        assert_eq(metadata.status_code, Some(200))
        assert_eq(metadata.id, Some("chat-1"))
        assert_eq(metadata.model_id, Some("test-model"))
        assert_eq(metadata.created_at, Some(1700000000))
      }
      None => fail("expected response metadata")
    }
    json_inspect(response.provider_metadata["local-test.chat"], content={
      "trace_id": "trace-1",
    })
  }
}

///|
async test "JSON transport retries a transient server response" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          if request_count == 0 {
            connection.send_response(500, "Server Error")
            connection.write("temporary failure")
          } else {
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write(
              "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"retried\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}",
            )
          }
          request_count = request_count + 1
        },
        max_connections=2,
      )
    }
    let model = openai_compatible(
      provider_name="retry-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      idle_timeout_ms=2_000,
    )
    let policy : @moonai.RetryPolicy = {
      max_retries: 1,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    let response = @moonai.generate_text(
      model,
      prompt="retry me",
      retry_policy=policy,
    )
    assert_eq(response.text, "retried")
    assert_eq(request_count, 2)
  }
}

///|
async test "JSON transport does not retry a client error" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          request_count = request_count + 1
          connection.send_response(400, "Bad Request")
          connection.write("invalid request")
        },
        max_connections=1,
      )
    }
    let model = openai_compatible(
      provider_name="client-error-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      idle_timeout_ms=2_000,
    )
    let policy : @moonai.RetryPolicy = {
      max_retries: 2,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    try
      @moonai.generate_text(model, prompt="do not retry", retry_policy=policy)
    catch {
      _ => ()
    } noraise {
      _ => fail("expected a client error")
    }
    assert_eq(request_count, 1)
  }
}

///|
async test "cancellation interrupts retry backoff" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let token = @moonai.CancellationToken::new()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          request_count = request_count + 1
          connection.send_response(500, "Server Error")
          connection.write("temporary failure")
        },
        max_connections=1,
      )
    }
    group.spawn_bg(no_wait=true) <| () => {
      @async.sleep(10)
      token.cancel()
    }
    let model = openai_compatible(
      provider_name="cancel-retry-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      idle_timeout_ms=2_000,
    )
    let policy : @moonai.RetryPolicy = {
      max_retries: 2,
      initial_delay_ms: 200,
      max_delay_ms: 200,
      backoff_factor: 1.0,
    }
    try
      @moonai.generate_text(
        model,
        prompt="cancel retry",
        retry_policy=policy,
        cancellation_token=token,
      )
    catch {
      @moonai.CancellationError => ()
      error => fail("unexpected cancellation error: \{error}")
    } noraise {
      _ => fail("expected cancellation during retry")
    }
    assert_eq(request_count, 1)
  }
}

///|
async test "cancelled token prevents a provider request" {
  let token = @moonai.CancellationToken::new()
  token.cancel()
  let model = openai_compatible(
    provider_name="cancel-test",
    base_url="http://127.0.0.1:1/v1",
    model_id="test-model",
    idle_timeout_ms=100,
  )
  try
    @moonai.generate_text(model, prompt="cancel me", cancellation_token=token)
  catch {
    @moonai.CancellationError => ()
    error => fail("unexpected cancellation error: \{error}")
  } noraise {
    _ => fail("expected cancellation")
  }
}

///|
async test "SSE transport retries before stream start" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          if request_count == 0 {
            connection.send_response(503, "Unavailable")
            connection.write("try again")
          } else {
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
            })
            connection.write(
              "data: {\"choices\":[{\"delta\":{\"content\":\"retried stream\"},\"finish_reason\":\"stop\"}]}\n\n",
            )
            connection.write("data: [DONE]\n\n")
          }
          request_count = request_count + 1
        },
        max_connections=2,
      )
    }
    let model = openai_compatible(
      provider_name="sse-retry-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      idle_timeout_ms=2_000,
    )
    let policy : @moonai.RetryPolicy = {
      max_retries: 1,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    let response = @moonai.stream_text(
      model,
      prompt="retry stream",
      retry_policy=policy,
    )
    assert_eq(response.text, "retried stream")
    assert_eq(request_count, 2)
  }
}

///|
async test "SSE transport does not retry after stream events are emitted" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          request_count = request_count + 1
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}\n\n",
          )
        },
        max_connections=1,
      )
    }
    let model = openai_compatible(
      provider_name="sse-no-retry-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      idle_timeout_ms=2_000,
    )
    let policy : @moonai.RetryPolicy = {
      max_retries: 2,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    try
      @moonai.stream_text(model, prompt="partial", retry_policy=policy)
    catch {
      _ => ()
    } noraise {
      _ => fail("expected an incomplete stream error")
    }
    assert_eq(request_count, 1)
  }
}

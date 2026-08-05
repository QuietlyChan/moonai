///|
async fn bind_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
async test "streamText drives an Open Responses HTTP SSE request" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/responses")
          assert_true(
            request.headers.get("authorization") is Some("Bearer test-key"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"model\":\"test-model\""))
          assert_true(request_body.contains("\"type\":\"input_text\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"msg_1\",\"type\":\"message\"},\"id\":\"resp-stream\",\"model\":\"test-model\",\"created_at\":1700000003,\"provider_metadata\":{\"local-test.responses\":{\"stream_trace\":\"rs-1\"}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"Hello Responses\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"msg_1\",\"type\":\"message\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":2,\"output_tokens\":3,\"total_tokens\":5}}}\n\n",
          )
        },
        max_connections=1,
      )
    }
    let model = open_responses_wire(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(model)
      as &@provider.LanguageModelV4
    let deltas : Array[String] = []
    let response = @ai.stream_text(model, prompt="hello", on_event=event => {
      match event {
        @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
        _ => ()
      }
    })
    assert_eq(deltas.join(""), "Hello Responses")
    assert_eq(response.finish_reason.unified, @provider.V4FinishStop)
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(3))
    match response.response {
      Some(metadata) => {
        assert_eq(metadata.status_code, Some(200))
        assert_eq(metadata.id, Some("resp-stream"))
        assert_eq(metadata.model_id, Some("test-model"))
        assert_eq(metadata.created_at, Some(1700000003))
      }
      None => fail("expected streaming response metadata")
    }
    json_inspect(response.provider_metadata["local-test.responses"], content={
      "stream_trace": "rs-1",
    })
  }
}

///|
async test "generateText drives an Open Responses JSON request" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/responses")
          assert_true(
            request.headers.get("x-request-id") is Some("responses-generate"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"model\":\"test-model\""))
          assert_false(request_body.contains("\"stream\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"resp_1\",\"model\":\"test-model\",\"created_at\":1700000002,\"status\":\"completed\",\"provider_metadata\":{\"local-test.responses\":{\"trace_id\":\"r-1\"}},\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello generate\"}]}],\"usage\":{\"input_tokens\":2,\"output_tokens\":2,\"total_tokens\":4}}",
          )
        },
        max_connections=1,
      )
    }
    let model = open_responses_wire(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(model)
      as &@provider.LanguageModelV4
    let response = @ai.generate_text(model, prompt="hello", headers={
      "X-Request-Id": "responses-generate",
    })
    assert_eq(response.text(), "Hello generate")
    assert_eq(response.finish_reason.unified, @provider.V4FinishStop)
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(2))
    match response.request {
      Some(request) => {
        assert_true(request.body.contains("\"model\":\"test-model\""))
        assert_false(request.body.contains("\"stream\""))
      }
      None => fail("expected request metadata")
    }
    match response.response {
      Some(metadata) => {
        assert_eq(metadata.status_code, Some(200))
        assert_eq(metadata.id, Some("resp_1"))
        assert_eq(metadata.model_id, Some("test-model"))
        assert_eq(metadata.created_at, Some(1700000002))
      }
      None => fail("expected response metadata")
    }
    json_inspect(response.provider_metadata["local-test.responses"], content={
      "trace_id": "r-1",
    })
  }
}

///|
async test "HTTP 200 response errors use the typed API call boundary" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
            "X-Error-Id": "semantic-error",
          })
          connection.write(
            "{\"status\":\"failed\",\"error\":{\"message\":\"context exhausted\",\"code\":\"context_length\"}}",
          )
        },
        max_connections=1,
      )
    }
    let model = open_responses_wire(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(model)
      as &@provider.LanguageModelV4
    try
      @ai.generate_text(
        model,
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
      )
    catch {
      @provider.APICallError(
        message="context exhausted",
        status_code=400,
        request_body~,
        response_headers~,
        response_body~,
        is_retryable=false,
        ..
      ) => {
        assert_true(request_body.contains("\"model\":\"test-model\""))
        assert_eq(response_headers["x-error-id"], "semantic-error")
        assert_true(response_body.contains("context_length"))
      }
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a typed semantic response error")
    }
  }
}

///|
async test "HTTP 200 responses without output use the typed API call boundary" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}",
          )
        },
        max_connections=1,
      )
    }
    let model = open_responses_wire(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(model)
      as &@provider.LanguageModelV4
    try
      @ai.generate_text(
        model,
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
      )
    catch {
      @provider.APICallError(
        message="Responses API returned no output (max_output_tokens)",
        status_code=500,
        is_retryable=false,
        ..
      ) => ()
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a typed missing-output response error")
    }
  }
}

///|
async test "JSON provider failures expose typed API call diagnostics" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(400, "Bad Request", extra_headers={
            "Content-Type": "application/json",
            "X-Error-Id": "error-json",
          })
          connection.write(
            "{\"error\":{\"message\":\"invalid request\",\"type\":\"bad_request\",\"param\":\"input\",\"code\":\"invalid\"}}",
          )
        },
        max_connections=1,
      )
    }
    let model = open_responses_wire(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(model)
      as &@provider.LanguageModelV4
    try
      @ai.generate_text(
        model,
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
      )
    catch {
      @provider.APICallError(
        message~,
        url~,
        request_body~,
        status_code~,
        response_headers~,
        response_body~,
        is_retryable~,
        ..
      ) => {
        assert_eq(message, "invalid request")
        assert_true(url.has_suffix("/v1/responses"))
        assert_true(request_body.contains("\"model\":\"test-model\""))
        assert_eq(status_code, 400)
        assert_eq(response_headers["x-error-id"], "error-json")
        assert_true(response_body.contains("bad_request"))
        assert_eq(is_retryable, false)
      }
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a typed API call error")
    }
  }
}

///|
async test "SSE provider failures use the same typed API call error" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(429, "Too Many Requests", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"error\":{\"message\":\"rate limited\",\"type\":\"rate_limit\",\"param\":\"\",\"code\":\"rate_limit\"}}",
          )
        },
        max_connections=1,
      )
    }
    let model = open_responses_wire(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(model)
      as &@provider.LanguageModelV4
    try
      @ai.stream_text(
        model,
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
      )
    catch {
      @provider.APICallError(
        message="rate limited",
        status_code=429,
        is_retryable=true,
        ..
      ) => ()
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a typed SSE API call error")
    }
  }
}

///|
async test "V4 generate preserves raw usage and raw finish reason" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"summary\":\"detailed\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"resp-v4\",\"model\":\"test-model\",\"created_at\":1700000010,\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"},\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"partial\"}]}],\"usage\":{\"input_tokens\":12,\"input_tokens_details\":{\"cached_tokens\":5},\"output_tokens\":9,\"output_tokens_details\":{\"reasoning_tokens\":3},\"total_tokens\":21}}",
          )
        },
        max_connections=1,
      )
    }
    let concrete = open_responses_wire(
      model_id="test-model",
      provider_name="local-v4",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(concrete)
      as &@provider.LanguageModelV4
    let result = @ai.generate_text(
      model,
      prompt="hello",
      top_k=20.0,
      seed=42,
      provider_options=OpenResponsesLanguageModelOptions::new(
        reasoning_summary=ReasoningSummaryDetailed,
      ).to_provider_options(provider_name="local-v4"),
    )
    assert_eq(result.finish_reason.unified, @provider.V4FinishLength)
    assert_eq(result.finish_reason.raw, Some("max_output_tokens"))
    assert_eq(result.usage.input_tokens.total, Some(12))
    assert_eq(result.usage.input_tokens.no_cache, Some(7))
    assert_eq(result.usage.input_tokens.cache_read, Some(5))
    assert_eq(result.usage.output_tokens.total, Some(9))
    assert_eq(result.usage.output_tokens.text, Some(6))
    assert_eq(result.usage.output_tokens.reasoning, Some(3))
    assert_true(result.usage.raw is Some({ "total_tokens": 21, .. }))
    assert_eq(result.warnings.length(), 2)
    assert_true(result.warnings[0] is @provider.Unsupported(feature="topK", ..))
    assert_true(result.warnings[1] is @provider.Unsupported(feature="seed", ..))
  }
}

///|
async test "V4 stream bundles warnings and emits native terminal metadata" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"msg-v4\",\"type\":\"message\"},\"id\":\"resp-stream-v4\",\"model\":\"test-model\",\"created_at\":1700000011}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg-v4\",\"delta\":\"partial\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.incomplete\",\"response\":{\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"content_filter\"},\"usage\":{\"input_tokens\":4,\"input_tokens_details\":{\"cached_tokens\":1},\"output_tokens\":2,\"output_tokens_details\":{\"reasoning_tokens\":1},\"total_tokens\":6}}}\n\n",
          )
        },
        max_connections=1,
      )
    }
    let concrete = open_responses_wire(
      model_id="test-model",
      provider_name="local-v4",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      idle_timeout_ms=2_000,
    )
    let model = OpenResponsesLanguageModelV4::new(concrete)
      as &@provider.LanguageModelV4
    let mut starts = 0
    let mut standalone_warnings = 0
    let mut finish_raw : String? = None
    let mut finish_no_cache : Int? = None
    let result = @ai.stream_text(model, prompt="hello", top_k=20.0, on_event=event => {
      match event {
        @provider.V4StreamStart(warnings~) => {
          starts = starts + 1
          assert_eq(warnings.length(), 1)
        }
        @provider.V4Warning(_) => standalone_warnings = standalone_warnings + 1
        @provider.V4Finish(usage~, reason~, ..) => {
          finish_raw = reason.raw
          finish_no_cache = usage.input_tokens.no_cache
        }
        _ => ()
      }
    })
    assert_eq(starts, 1)
    assert_eq(standalone_warnings, 0)
    assert_eq(finish_raw, Some("content_filter"))
    assert_eq(finish_no_cache, Some(3))
    assert_eq(result.finish_reason.unified, @provider.V4FinishContentFilter)
    assert_eq(result.finish_reason.raw, Some("content_filter"))
    assert_eq(result.usage.output_tokens.reasoning, Some(1))
    assert_true(result.usage.raw is Some({ "total_tokens": 6, .. }))
    assert_eq(result.warnings.length(), 1)
    assert_eq(result.response.unwrap().id, Some("resp-stream-v4"))
  }
}

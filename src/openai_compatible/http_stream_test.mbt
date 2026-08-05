///|
async fn bind_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
fn compatible_v4(
  model : OpenAICompatibleLanguageModelV4,
) -> &@provider.LanguageModelV4 {
  model as &@provider.LanguageModelV4
}

///|
async test "streamText drives an OpenAI-compatible HTTP SSE request" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/chat/completions?api-version=2026-08")
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
      query_params={ "api-version": "2026-08" },
      idle_timeout_ms=2_000,
    )
    let deltas : Array[String] = []
    let response = @ai.stream_text(compatible_v4(model), prompt="hello", on_event=event => {
      match event {
        @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
        _ => ()
      }
    })
    assert_eq(deltas.join(""), "Hello compatible")
    assert_eq(response.finish_reason.unified, @provider.V4FinishStop)
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(2))
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
async test "OpenAI-compatible V4 preserves native stream usage and finish reason" {
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
            "data: {\"id\":\"v4-stream\",\"model\":\"test-model\",\"created\":1700000002,\"choices\":[{\"delta\":{\"content\":\"compatible\"},\"finish_reason\":\"stop\"}]}\n\n",
          )
          connection.write(
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":3,\"total_tokens\":7}}\n\n",
          )
          connection.write("data: [DONE]\n\n")
        },
        max_connections=1,
      )
    }
    let concrete = openai_compatible(
      provider_name="local-v4",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let model = concrete as &@provider.LanguageModelV4
    let mut finish_raw : String? = None
    let result = @ai.stream_text(model, prompt="hello", on_event=event => {
      match event {
        @provider.V4Finish(reason~, ..) => finish_raw = reason.raw
        _ => ()
      }
    })
    assert_eq(result.finish_reason.unified, @provider.V4FinishStop)
    assert_eq(result.finish_reason.raw, Some("stop"))
    assert_eq(finish_raw, Some("stop"))
    assert_eq(result.usage.input_tokens.total, Some(4))
    assert_eq(result.usage.output_tokens.total, Some(3))
    assert_eq(result.response.unwrap().id, Some("v4-stream"))
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
    let response = @ai.generate_text(compatible_v4(model), prompt="hello", headers={
      "X-Request-Id": "chat-generate",
    })
    assert_eq(response.text(), "Hello generate")
    assert_eq(response.finish_reason.unified, @provider.V4FinishStop)
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(2))
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
async test "compatible chat applies custom metadata and usage converters" {
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
            "{\"trace\":\"trace-custom\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"custom hooks\"},\"finish_reason\":\"stop\"}],\"usage\":{\"input\":7,\"output\":3}}",
          )
        },
        max_connections=1,
      )
    }
    let metadata_extractor = OpenAICompatibleMetadataExtractor::new(
      extract_metadata=response => {
        let trace = match response {
          { "trace": String(value), .. } => value
          _ => ""
        }
        Map([("vendor", ({ "trace": trace } : Json))])
      },
      create_stream_extractor=() => {
        OpenAICompatibleStreamMetadataExtractor::new(process_chunk=_ => (), build_metadata=() => {
          Map([])
        })
      },
    )
    let model = openai_compatible(
      provider_name="custom-hooks",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      metadata_extractor~,
      convert_usage=usage => {
        let input_tokens = @provider_utils.json_int_field(usage, "input")
        let output_tokens = @provider_utils.json_int_field(usage, "output")
        {
          input_tokens,
          output_tokens,
          total_tokens: input_tokens + output_tokens,
          reasoning_tokens: 0,
          cached_input_tokens: 0,
          cache_write_input_tokens: 0,
        }
      },
      idle_timeout_ms=2_000,
    )
    let response = @ai.generate_text(compatible_v4(model), prompt="hello")
    assert_eq(response.text(), "custom hooks")
    assert_eq(response.usage.input_tokens.total, Some(7))
    assert_eq(response.usage.output_tokens.total, Some(3))
    json_inspect(response.provider_metadata["vendor"], content={
      "trace": "trace-custom",
    })
  }
}

///|
async test "compatible stream metadata extractor accumulates chunks" {
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
            "data: {\"choices\":[{\"delta\":{\"content\":\"counted\"},\"finish_reason\":\"stop\"}]}\n\n",
          )
          connection.write(
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}\n\n",
          )
          connection.write("data: [DONE]\n\n")
        },
        max_connections=1,
      )
    }
    let metadata_extractor = OpenAICompatibleMetadataExtractor::new(
      extract_metadata=_ => Map([]),
      create_stream_extractor=() => {
        let chunks = Ref(0)
        OpenAICompatibleStreamMetadataExtractor::new(
          process_chunk=_ => chunks.val = chunks.val + 1,
          build_metadata=() => {
            Map([("vendor", ({ "chunk_count": chunks.val } : Json))])
          },
        )
      },
    )
    let model = openai_compatible(
      provider_name="stream-hooks",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      metadata_extractor~,
      idle_timeout_ms=2_000,
    )
    let deltas : Array[String] = []
    let response = @ai.stream_text(compatible_v4(model), prompt="hello", on_event=event => {
      match event {
        @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
        _ => ()
      }
    })
    assert_eq(deltas.join(""), "counted")
    json_inspect(response.provider_metadata["vendor"], content={
      "chunk_count": 2,
    })
  }
}

///|
async test "custom error structure can mark a provider response retryable" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          if request_count == 0 {
            connection.send_response(400, "Bad Request", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write(
              "{\"problem\":{\"detail\":\"capacity is warming\"}}",
            )
          } else {
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write(
              "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"retried custom error\"},\"finish_reason\":\"stop\"}]}",
            )
          }
          request_count = request_count + 1
        },
        max_connections=2,
      )
    }
    let error_structure = OpenAICompatibleErrorStructure::new(
      error_to_message=error => {
        match error {
          { "problem": { "detail": String(message), .. }, .. } => Some(message)
          _ => None
        }
      },
      is_retryable=(status_code, _error) => {
        if status_code == 400 {
          Some(true)
        } else {
          None
        }
      },
    )
    let model = openai_compatible(
      provider_name="custom-error",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="test-model",
      error_structure~,
      idle_timeout_ms=2_000,
    )
    let response = @ai.generate_text(
      compatible_v4(model),
      prompt="retry custom response",
      retry_policy={
        max_retries: 1,
        initial_delay_ms: 0,
        max_delay_ms: 0,
        backoff_factor: 1.0,
      },
    )
    assert_eq(response.text(), "retried custom error")
    assert_eq(request_count, 2)
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
    let policy : @provider.RetryPolicy = {
      max_retries: 1,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    let response = @ai.generate_text(
      compatible_v4(model),
      prompt="retry me",
      retry_policy=policy,
    )
    assert_eq(response.text(), "retried")
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
    let policy : @provider.RetryPolicy = {
      max_retries: 2,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    try
      @ai.generate_text(
        compatible_v4(model),
        prompt="do not retry",
        retry_policy=policy,
      )
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
    let token = @provider.CancellationToken::new()
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
    let policy : @provider.RetryPolicy = {
      max_retries: 2,
      initial_delay_ms: 200,
      max_delay_ms: 200,
      backoff_factor: 1.0,
    }
    try
      @ai.generate_text(
        compatible_v4(model),
        prompt="cancel retry",
        retry_policy=policy,
        cancellation_token=token,
      )
    catch {
      @provider.CancellationError => ()
      error => fail("unexpected cancellation error: \{error}")
    } noraise {
      _ => fail("expected cancellation during retry")
    }
    assert_eq(request_count, 1)
  }
}

///|
async test "cancelled token prevents a provider request" {
  let token = @provider.CancellationToken::new()
  token.cancel()
  let model = openai_compatible(
    provider_name="cancel-test",
    base_url="http://127.0.0.1:1/v1",
    model_id="test-model",
    idle_timeout_ms=100,
  )
  try
    @ai.generate_text(
      compatible_v4(model),
      prompt="cancel me",
      cancellation_token=token,
    )
  catch {
    @provider.CancellationError => ()
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
    let policy : @provider.RetryPolicy = {
      max_retries: 1,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    let deltas : Array[String] = []
    @ai.stream_text(
      compatible_v4(model),
      prompt="retry stream",
      retry_policy=policy,
      on_event=event => {
        match event {
          @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
          _ => ()
        }
      },
    )
    |> ignore
    assert_eq(deltas.join(""), "retried stream")
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
    let policy : @provider.RetryPolicy = {
      max_retries: 2,
      initial_delay_ms: 0,
      max_delay_ms: 0,
      backoff_factor: 1.0,
    }
    try
      @ai.stream_text(
        compatible_v4(model),
        prompt="partial",
        retry_policy=policy,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("expected an incomplete stream error")
    }
    assert_eq(request_count, 1)
  }
}

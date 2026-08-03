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
    let model = open_responses(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let response = @moonai.stream_text(model, prompt="hello")
    assert_eq(response.text, "Hello Responses")
    assert_eq(response.finish_reason, @moonai.Stop)
    assert_eq(response.usage.total_tokens, 5)
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
    let model = open_responses(
      model_id="test-model",
      provider_name="local-test",
      url="http://127.0.0.1:\{server.addr.port()}/v1/responses",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let response = @moonai.generate_text(model, prompt="hello", headers={
      "X-Request-Id": "responses-generate",
    })
    assert_eq(response.text, "Hello generate")
    assert_eq(response.finish_reason, @moonai.Stop)
    assert_eq(response.usage.total_tokens, 4)
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

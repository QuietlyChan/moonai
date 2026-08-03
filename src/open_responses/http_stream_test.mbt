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
            "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"msg_1\",\"type\":\"message\"}}\n\n",
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
  }
}

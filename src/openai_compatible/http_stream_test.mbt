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
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello compatible\"},\"finish_reason\":\"stop\"}]}\n\n",
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
  }
}

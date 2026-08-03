///|
async test "complete and stream_completion drive OpenAI-compatible requests" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/completions")
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"prompt\":\"MoonBit is\""))
          if request_count == 0 {
            assert_true(
              request.headers.get("x-request-id") is Some("completion-generate"),
            )
            assert_false(request_body.contains("\"stream\""))
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write(
              "{\"choices\":[{\"text\":\" productive\",\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":1,\"total_tokens\":3}}",
            )
          } else {
            assert_true(request_body.contains("\"stream\":true"))
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
            })
            connection.write(
              "data: {\"choices\":[{\"text\":\" fast\",\"finish_reason\":null}]}\n\n",
            )
            connection.write(
              "data: {\"choices\":[{\"text\":\".\",\"finish_reason\":\"stop\"}]}\n\n",
            )
            connection.write(
              "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":2,\"total_tokens\":4}}\n\n",
            )
            connection.write("data: [DONE]\n\n")
          }
          request_count = request_count + 1
        },
        max_connections=2,
      )
    }
    let model = create_openai_compatible(
      provider_name="local-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      api_key="test-key",
      idle_timeout_ms=2_000,
    ).completion_model("completion-model")
    let generated = @moonai.complete(model, "MoonBit is", headers={
      "X-Request-Id": "completion-generate",
    })
    let streamed = @moonai.stream_completion(model, "MoonBit is")
    assert_eq(generated.text, " productive")
    assert_eq(generated.usage.total_tokens, 3)
    assert_eq(streamed.text, " fast.")
    assert_eq(streamed.usage.total_tokens, 4)
  }
}

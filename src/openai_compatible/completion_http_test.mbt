///|
async test "V4 generate_text and stream_text drive compatible completions" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/completions")
          let request_body = body.read_all().text()
          match @json.parse(request_body) {
            { "prompt": String(value), .. } =>
              assert_eq(value, "user:\nMoonBit is\n\nassistant:\n")
            _ => fail("completion request has no prompt")
          }
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
            assert_false(request_body.contains("\"top_k\""))
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
    let generated = @ai.generate_text(model, prompt="MoonBit is", headers={
      "X-Request-Id": "completion-generate",
    })
    let deltas : Array[String] = []
    let mut starts = 0
    let streamed = @ai.stream_text(model, prompt="MoonBit is", top_k=20.0, on_event=event => {
      match event {
        @provider.V4StreamStart(warnings~) => {
          starts = starts + 1
          assert_true(
            warnings.any(warning => {
              warning is @provider.Unsupported(feature="topK", ..)
            }),
          )
        }
        @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
        _ => ()
      }
    })
    assert_eq(generated.text(), " productive")
    assert_eq(generated.usage.input_tokens.total, Some(2))
    assert_eq(starts, 1)
    assert_eq(deltas.join(""), " fast.")
    assert_eq(streamed.usage.output_tokens.total, Some(2))
  }
}

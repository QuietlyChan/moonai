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
            "{\"id\":\"msg_1\",\"model\":\"claude-sonnet-4-6\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"brief\"},{\"type\":\"text\",\"text\":\"done\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":2,\"output_tokens\":3}}",
          )
        },
        max_connections=1,
      )
    }
    let model = AnthropicLanguageModelV4::new(
        create_anthropic(
          api_key="test-key",
          base_url="http://127.0.0.1:\{server.addr.port()}/v1",
          beta_features=["configured-beta"],
          idle_timeout_ms=2_000,
        ).messages_wire("claude-sonnet-4-6"),
      )
      as &@provider.LanguageModelV4
    let response = @ai.generate_text(model, prompt="hello", provider_options={
      "anthropic": { "anthropicBeta": ["custom-beta"] },
    })
    assert_eq(response.text(), "done")
    assert_eq(response.reasoning(), "brief")
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(3))
  }
}

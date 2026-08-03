///|
async fn bind_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
async test "official OpenAI provider composes chat and responses protocols" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if request.path == "/v1/chat/completions" {
            connection.write(
              "data: {\"choices\":[{\"delta\":{\"content\":\"chat\"},\"finish_reason\":\"stop\"}]}\n\n",
            )
            connection.write("data: [DONE]\n\n")
          } else {
            assert_eq(request.path, "/v1/responses")
            connection.write(
              "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"responses\"}\n\n",
            )
            connection.write(
              "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n",
            )
            connection.write("data: [DONE]\n\n")
          }
        },
        max_connections=2,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let chat = @moonai.stream_text(provider.chat("chat-model"), prompt="hello")
    let responses = @moonai.stream_text(
      provider.language_model("responses-model"),
      prompt="hello",
    )
    assert_eq(chat.text, "chat")
    assert_eq(responses.text, "responses")
  }
}

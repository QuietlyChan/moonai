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

///|
async test "official OpenAI provider composes non-streaming generation" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          let request_body = body.read_all().text()
          assert_false(request_body.contains("\"stream\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          if request.path == "/v1/chat/completions" {
            connection.write(
              "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"chat generate\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}",
            )
          } else {
            assert_eq(request.path, "/v1/responses")
            connection.write(
              "{\"id\":\"resp_1\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"responses generate\"}]}],\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}",
            )
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
    let chat = @moonai.generate_text(
      provider.chat("chat-model"),
      prompt="hello",
    )
    let responses = @moonai.generate_text(
      provider.language_model("responses-model"),
      prompt="hello",
    )
    assert_eq(chat.text, "chat generate")
    assert_eq(responses.text, "responses generate")
  }
}

///|
async test "official OpenAI provider exposes embedding models" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/embeddings")
          let request_body = body.read_all().text()
          assert_true(
            request_body.contains("\"model\":\"text-embedding-3-small\""),
          )
          assert_true(request_body.contains("\"input\":[\"MoonBit\"]"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"data\":[{\"index\":0,\"embedding\":[0.25,0.5]}],\"usage\":{\"prompt_tokens\":1}}",
          )
        },
        max_connections=1,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let result = @moonai.embed(
      provider.embedding("text-embedding-3-small"),
      "MoonBit",
    )
    assert_eq(result.embedding, [0.25, 0.5])
    assert_eq(result.usage.input_tokens, 1)
  }
}

///|
async test "official OpenAI provider exposes completion models" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/completions")
          let request_body = body.read_all().text()
          assert_true(
            request_body.contains("\"model\":\"gpt-3.5-turbo-instruct\""),
          )
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"choices\":[{\"text\":\" complete\",\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}",
          )
        },
        max_connections=1,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let result = @moonai.complete(
      provider.completion("gpt-3.5-turbo-instruct"),
      "MoonBit",
    )
    assert_eq(result.text, " complete")
    assert_eq(result.usage.total_tokens, 2)
  }
}

///|
async test "official OpenAI image models apply model-specific limits and format" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/images/generations")
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"n\":1"))
          if request_count < 2 {
            assert_true(request_body.contains("\"model\":\"dall-e-3\""))
            assert_true(
              request_body.contains("\"response_format\":\"b64_json\""),
            )
          } else {
            assert_true(request_body.contains("\"model\":\"gpt-image-1\""))
            assert_false(request_body.contains("\"response_format\""))
          }
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"data\":[{\"b64_json\":\"image-data\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}",
          )
          request_count = request_count + 1
        },
        max_connections=3,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let dalle = @moonai.generate_image(provider.image("dall-e-3"), "Moon", n=2)
    let gpt_image = @moonai.generate_image(
      provider.image_model("gpt-image-1"),
      "MoonBit",
    )
    assert_eq(dalle.images.length(), 2)
    assert_eq(dalle.usage.total_tokens, 4)
    assert_eq(gpt_image.images.length(), 1)
  }
}

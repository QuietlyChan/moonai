///|
async test "embed and embedMany drive OpenAI-compatible embedding requests" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/embeddings")
          assert_true(
            request.headers.get("authorization") is Some("Bearer test-key"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"encoding_format\":\"float\""))
          assert_true(request_body.contains("\"dimensions\":3"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          if request_count == 0 {
            assert_true(
              request.headers.get("x-request-id") is Some("embedding-single"),
            )
            assert_true(request_body.contains("\"input\":[\"hello\"]"))
            connection.write(
              "{\"data\":[{\"index\":0,\"embedding\":[0.1,0.2,0.3]}],\"usage\":{\"prompt_tokens\":2}}",
            )
          } else if request_count == 1 {
            assert_true(request_body.contains("\"input\":[\"one\",\"two\"]"))
            connection.write(
              "{\"data\":[{\"index\":0,\"embedding\":[1,2,3]},{\"index\":1,\"embedding\":[4,5,6]}],\"usage\":{\"prompt_tokens\":4}}",
            )
          } else {
            assert_true(request_body.contains("\"input\":[\"three\"]"))
            connection.write(
              "{\"data\":[{\"index\":0,\"embedding\":[7,8,9]}],\"usage\":{\"prompt_tokens\":2}}",
            )
          }
          request_count = request_count + 1
        },
        max_connections=3,
      )
    }
    let provider = create_openai_compatible(
      provider_name="local-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      api_key="test-key",
      idle_timeout_ms=2_000,
      max_embeddings_per_call=2,
    )
    let model = provider.embedding_model("embedding-model")
    let single = @moonai.embed(model, "hello", dimensions=3, headers={
      "X-Request-Id": "embedding-single",
    })
    let many = @moonai.embedMany(model, ["one", "two", "three"], dimensions=3)
    assert_eq(single.embedding, [0.1, 0.2, 0.3])
    assert_eq(single.usage.input_tokens, 2)
    assert_eq(many.embeddings, [
      [1.0, 2.0, 3.0],
      [4.0, 5.0, 6.0],
      [7.0, 8.0, 9.0],
    ])
    assert_eq(many.usage.input_tokens, 6)
  }
}

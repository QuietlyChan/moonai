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
              "{\"id\":\"emb-1\",\"model\":\"embedding-model\",\"created\":1700000010,\"provider_metadata\":{\"local-test.embedding\":{\"single\":true}},\"data\":[{\"index\":0,\"embedding\":[0.1,0.2,0.3]}],\"usage\":{\"prompt_tokens\":2}}",
            )
          } else if request_count == 1 {
            assert_true(request_body.contains("\"input\":[\"one\",\"two\"]"))
            connection.write(
              "{\"id\":\"emb-2\",\"model\":\"embedding-model\",\"provider_metadata\":{\"local-test.embedding\":{\"first_batch\":true}},\"data\":[{\"index\":0,\"embedding\":[1,2,3]},{\"index\":1,\"embedding\":[4,5,6]}],\"usage\":{\"prompt_tokens\":4}}",
            )
          } else {
            assert_true(request_body.contains("\"input\":[\"three\"]"))
            connection.write(
              "{\"id\":\"emb-3\",\"model\":\"embedding-model\",\"provider_metadata\":{\"local-test.embedding\":{\"last_batch\":true}},\"data\":[{\"index\":0,\"embedding\":[7,8,9]}],\"usage\":{\"prompt_tokens\":2}}",
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
    let single = @ai.embed(model, "hello", dimensions=3, headers={
      "X-Request-Id": "embedding-single",
    })
    let many = @ai.embedMany(model, ["one", "two", "three"], dimensions=3)
    assert_eq(single.embedding, [0.1, 0.2, 0.3])
    assert_eq(single.usage.input_tokens, 2)
    match single.request {
      Some(request) =>
        assert_true(request.body.contains("\"input\":[\"hello\"]"))
      None => fail("expected embedding request metadata")
    }
    assert_eq(single.response.unwrap().id, Some("emb-1"))
    assert_eq(single.response.unwrap().created_at, Some(1700000010))
    json_inspect(single.provider_metadata["local-test.embedding"], content={
      "single": true,
    })
    assert_eq(many.embeddings, [
      [1.0, 2.0, 3.0],
      [4.0, 5.0, 6.0],
      [7.0, 8.0, 9.0],
    ])
    assert_eq(many.usage.input_tokens, 6)
    assert_eq(many.response.unwrap().id, Some("emb-2"))
    json_inspect(many.provider_metadata["local-test.embedding"], content={
      "first_batch": true,
      "last_batch": true,
    })
  }
}

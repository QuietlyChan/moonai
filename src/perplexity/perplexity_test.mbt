///|
test "perplexity provider exposes chat and embedding models" {
  let provider = @perplexity.create_perplexity(api_key="pplx-test")
  let chat = provider.chat("sonar-pro")
  assert_eq(chat.provider(), "perplexity")
  assert_eq(chat.model_id(), "sonar-pro")
  assert_eq(chat.specification_version(), "v4")
  assert_true(
    chat.supported_urls()[0].matches_url("https://example.com/image.png"),
  )
  assert_eq(chat.supported_urls()[0].media_type(), "image/*")
  let embedding = provider.embedding("pplx-embed-v1")
  assert_eq(embedding.provider(), "perplexity.embedding")
  assert_eq(embedding.max_embeddings_per_call(), Some(512))
  assert_true(embedding.supports_parallel_calls())
}

///|
test "perplexity direct factory builds the same language model boundary" {
  let model = @perplexity.perplexity("sonar", api_key="pplx-test")
  assert_eq(model.provider(), "perplexity")
  assert_eq(model.model_id(), "sonar")
}

///|
async fn bind_perplexity_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
async test "Perplexity language generation uses Agent API while embeddings stay unchanged" {
  @async.with_task_group() <| group => {
    let server = bind_perplexity_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          let request_body = body.read_all().text()
          assert_true(
            request.headers.get("authorization") is Some("Bearer test-key"),
          )
          assert_true(request.headers.get("x-provider") is Some("configured"))
          match request.path {
            "/v1/agent" => {
              assert_true(request.headers.get("x-call") is Some("request"))
              assert_true(request_body.contains("\"preset\":\"fast\""))
              assert_true(request_body.contains("\"input\""))
              if request_body.contains("\"stream\":true") {
                connection.send_response(200, "OK", extra_headers={
                  "Content-Type": "text/event-stream",
                  "x-request-id": "agent-stream",
                })
                connection.write(
                  "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-stream\",\"created_at\":1727000001,\"model\":\"fast\",\"status\":\"in_progress\"}}\n\n",
                )
                connection.write(
                  "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg-stream\",\"delta\":\"streamed\"}\n\n",
                )
                connection.write(
                  "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-stream\",\"created_at\":1727000001,\"model\":\"fast\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"id\":\"msg-stream\",\"content\":[{\"type\":\"output_text\",\"text\":\"streamed\"}]}],\"usage\":{\"input_tokens\":3,\"output_tokens\":2}}}\n\n",
                )
              } else {
                assert_true(request_body.contains("\"max_output_tokens\":64"))
                connection.send_response(200, "OK", extra_headers={
                  "Content-Type": "application/json",
                  "x-request-id": "agent-request",
                })
                connection.write(
                  "{\"id\":\"resp-1\",\"created_at\":1727000000,\"model\":\"fast\",\"object\":\"response\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"answer\"}]}],\"usage\":{\"input_tokens\":2,\"output_tokens\":1}}",
                )
              }
            }
            "/v1/embeddings" => {
              assert_true(request_body.contains("\"model\":\"pplx-embed-v1\""))
              assert_true(
                request_body.contains("\"encoding_format\":\"base64_int8\""),
              )
              connection.send_response(200, "OK", extra_headers={
                "Content-Type": "application/json",
                "x-request-id": "embedding-request",
              })
              connection.write(
                "{\"data\":[{\"index\":0,\"embedding\":\"AAE=\"}],\"usage\":{\"prompt_tokens\":1}}",
              )
            }
            _ => fail("unexpected Perplexity request path: \{request.path}")
          }
        },
        max_connections=3,
      )
    }
    let provider = @perplexity.create_perplexity(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}",
      headers={ "x-provider": "configured" },
      idle_timeout_ms=2_000,
    )
    let generated = provider
      .chat("fast")
      .do_generate(
        @provider.LanguageModelV4CallOptions::new(
          @provider.LanguageModelV4Prompt::new([
            @provider.V4UserMessage(
              content=[
                @provider.V4PromptText(text="hello", provider_options=Map([])),
              ],
              provider_options=Map([]),
            ),
          ]),
          max_output_tokens=64,
          headers={ "x-call": "request" },
          retry_policy=@provider.RetryPolicy::none(),
        ),
      )
    assert_eq(generated.text(), "answer")
    assert_eq(generated.response.unwrap().id, Some("resp-1"))
    assert_eq(generated.response.unwrap().status_code, Some(200))

    let stream_parts : Array[@provider.LanguageModelV4StreamPart] = []
    let streamed = provider
      .chat("fast")
      .do_stream(
        @provider.LanguageModelV4CallOptions::new(
          @provider.LanguageModelV4Prompt::new([
            @provider.V4UserMessage(
              content=[
                @provider.V4PromptText(text="hello", provider_options=Map([])),
              ],
              provider_options=Map([]),
            ),
          ]),
          headers={ "x-call": "request" },
          retry_policy=@provider.RetryPolicy::none(),
        ),
        event => stream_parts.push(event),
      )
    assert_eq(streamed.response.unwrap().status_code, Some(200))
    assert_eq(streamed.response.unwrap().id, Some("resp-stream"))
    assert_true(
      stream_parts.any(event => {
        event is @provider.V4TextDelta(id="msg-stream", delta="streamed", ..)
      }),
    )
    assert_true(
      stream_parts.any(event => {
        event
        is @provider.V4Finish(
          reason={ unified: @provider.V4FinishStop, .. },
          usage={ input_tokens: { total: Some(3), .. }, .. },
          ..
        )
      }),
    )

    let embedded = provider
      .embedding("pplx-embed-v1")
      .do_embed(
        @provider.EmbeddingModelV4CallOptions::new(
          ["hello"],
          retry_policy=@provider.RetryPolicy::none(),
        ),
      )
    assert_eq(embedded.embeddings, [[0.0, 1.0]])
    assert_eq(embedded.response.unwrap().status_code, Some(200))
  }
}

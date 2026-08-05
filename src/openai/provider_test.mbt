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
          assert_true(
            request.headers.get("authorization") is Some("Bearer override-key"),
          )
          assert_true(
            request.headers.get("openai-organization") is Some("org-test"),
          )
          assert_true(
            request.headers.get("openai-project") is Some("proj-test"),
          )
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if request.path == "/v1/chat/completions" {
            connection.write(
              "data: {\"choices\":[{\"delta\":{\"content\":\"chat\"},\"finish_reason\":\"stop\",\"logprobs\":{\"content\":[{\"token\":\"chat\",\"logprob\":-0.1}]}}]}\n\n",
            )
            connection.write(
              "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2,\"completion_tokens_details\":{\"accepted_prediction_tokens\":4,\"rejected_prediction_tokens\":1}}}\n\n",
            )
            connection.write("data: [DONE]\n\n")
          } else {
            assert_eq(request.path, "/v1/responses")
            connection.write(
              "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"responses\",\"logprobs\":[{\"token\":\"responses\",\"logprob\":-0.3}]}\n\n",
            )
            connection.write(
              "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_stream\",\"status\":\"completed\",\"service_tier\":\"priority\",\"reasoning\":{\"context\":\"current_turn\"},\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n",
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
      organization="org-test",
      project="proj-test",
      headers={ "Authorization": "Bearer override-key" },
      idle_timeout_ms=2_000,
    )
    let chat_deltas : Array[String] = []
    let responses_deltas : Array[String] = []
    let chat = @ai.stream_text(provider.chat("chat-model"), prompt="hello", on_event=event => {
      match event {
        @provider.V4TextDelta(delta~, ..) => chat_deltas.push(delta)
        _ => ()
      }
    })
    let responses = @ai.stream_text(
      provider.language_model("responses-model"),
      prompt="hello",
      on_event=event => {
        match event {
          @provider.V4TextDelta(delta~, ..) => responses_deltas.push(delta)
          _ => ()
        }
      },
    )
    assert_eq(chat_deltas.join(""), "chat")
    assert_eq(responses_deltas.join(""), "responses")
    json_inspect(chat.provider_metadata["openai"], content={
      "logprobs": [{ "token": "chat", "logprob": -0.1 }],
      "acceptedPredictionTokens": 4,
      "rejectedPredictionTokens": 1,
    })
    json_inspect(responses.provider_metadata["openai"], content={
      "responseId": "resp_stream",
      "serviceTier": "priority",
      "reasoningContext": "current_turn",
      "logprobs": [[{ "token": "responses", "logprob": -0.3 }]],
    })
  }
}

///|
async test "OpenAI Responses V4 preserves native stream usage and finish reason" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg-v4\",\"delta\":\"partial\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"resp-v4\",\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"},\"usage\":{\"input_tokens\":12,\"input_tokens_details\":{\"cached_tokens\":5},\"output_tokens\":9,\"output_tokens_details\":{\"reasoning_tokens\":3},\"total_tokens\":21}}}\n\n",
          )
          connection.write("data: [DONE]\n\n")
        },
        max_connections=1,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let model = provider.responses("responses-model")
      as &@provider.LanguageModelV4
    let mut finish_raw : String? = None
    let result = @ai.stream_text(
      model,
      prompt="hello",
      retry_policy=@provider.RetryPolicy::none(),
      on_event=event => {
        match event {
          @provider.V4Finish(reason~, ..) => finish_raw = reason.raw
          _ => ()
        }
      },
    )
    assert_eq(result.finish_reason.unified, @provider.V4FinishLength)
    assert_eq(result.finish_reason.raw, Some("max_output_tokens"))
    assert_eq(finish_raw, Some("max_output_tokens"))
    assert_eq(result.usage.input_tokens.total, Some(12))
    assert_eq(result.usage.input_tokens.no_cache, Some(7))
    assert_eq(result.usage.output_tokens.reasoning, Some(3))
    assert_eq(result.response.unwrap().id, Some("resp-v4"))
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
              "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"chat generate\"},\"finish_reason\":\"stop\",\"logprobs\":{\"content\":[{\"token\":\"chat\",\"logprob\":-0.2}]}}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3,\"completion_tokens_details\":{\"accepted_prediction_tokens\":2,\"rejected_prediction_tokens\":3}}}",
            )
          } else {
            assert_eq(request.path, "/v1/responses")
            connection.write(
              "{\"id\":\"resp_1\",\"status\":\"completed\",\"service_tier\":\"flex\",\"reasoning\":{\"context\":\"all_turns\"},\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"responses generate\",\"logprobs\":[{\"token\":\"responses\",\"logprob\":-0.4}]}]}],\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}",
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
    let chat = @ai.generate_text(provider.chat("chat-model"), prompt="hello")
    let responses = @ai.generate_text(
      provider.language_model("responses-model"),
      prompt="hello",
    )
    assert_eq(chat.text(), "chat generate")
    assert_eq(responses.text(), "responses generate")
    json_inspect(chat.provider_metadata["openai"], content={
      "acceptedPredictionTokens": 2,
      "rejectedPredictionTokens": 3,
      "logprobs": [{ "token": "chat", "logprob": -0.2 }],
    })
    json_inspect(responses.provider_metadata["openai"], content={
      "responseId": "resp_1",
      "serviceTier": "flex",
      "reasoningContext": "all_turns",
      "logprobs": [[{ "token": "responses", "logprob": -0.4 }]],
    })
  }
}

///|
async test "OpenAI Responses maps an early provider error to APICallError" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
            "X-Error-Id": "early-error",
          })
          connection.write(
            "data: {\"type\":\"error\",\"error\":{\"message\":\"quota exceeded\",\"code\":\"insufficient_quota\"}}\n\n",
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
    try
      @ai.stream_text(
        provider.responses("responses-model"),
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
      )
      |> ignore
    catch {
      @provider.APICallError(
        message="quota exceeded",
        status_code=429,
        response_headers~,
        response_body~,
        is_retryable=true,
        ..
      ) => {
        assert_eq(response_headers["x-error-id"], "early-error")
        assert_true(response_body.contains("insufficient_quota"))
      }
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected an early Responses provider error")
    }
  }
}

///|
async test "OpenAI Responses maps response.failed before output to APICallError" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\",\"error\":{\"message\":\"service overloaded\",\"type\":\"server_error\",\"code\":\"overload\"}}}\n\n",
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
    try
      @ai.stream_text(
        provider.responses("responses-model"),
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
      )
      |> ignore
    catch {
      @provider.APICallError(
        message="service overloaded",
        status_code=503,
        is_retryable=true,
        ..
      ) => ()
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected response.failed to fail the call")
    }
  }
}

///|
async test "OpenAI Responses rejects a Chat Completions SSE payload" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"delta\":{\"content\":\"wrong endpoint\"}}]}\n\n",
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
    try
      @ai.stream_text(
        provider.responses("responses-model"),
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
      )
      |> ignore
    catch {
      @provider.APICallError(message~, status_code=400, is_retryable=false, ..) =>
        assert_true(message.contains("Chat Completions"))
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a protocol mismatch error")
    }
  }
}

///|
async test "OpenAI Responses keeps post-output errors in the stream" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"partial\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"error\",\"error\":{\"message\":\"late failure\",\"code\":\"server_error\"}}\n\n",
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
    let events : Array[@provider.LanguageModelV4StreamPart] = []
    let result = @ai.stream_text(
      provider.responses("responses-model"),
      prompt="hello",
      retry_policy=@provider.RetryPolicy::none(),
      on_event=event => events.push(event),
    )
    assert_true(
      events.any(event => event is @provider.V4TextDelta(delta="partial", ..)),
    )
    assert_eq(result.finish_reason.unified, @provider.V4FinishError)
    assert_true(events.any(event => event is @provider.V4Error("late failure")))
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
          assert_true(request_body.contains("\"dimensions\":128"))
          assert_true(request_body.contains("\"user\":\"embedding-user\""))
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
    let result = @ai.embed(
      provider.embedding("text-embedding-3-small"),
      "MoonBit",
      provider_options={
        "openai": { "dimensions": 128, "user": "embedding-user" },
      },
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
          assert_true(request_body.contains("\"echo\":true"))
          assert_true(request_body.contains("\"logit_bias\":{\"42\":-1"))
          assert_true(request_body.contains("\"logprobs\":2"))
          assert_true(request_body.contains("\"user\":\"completion-user\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"choices\":[{\"text\":\" complete\",\"finish_reason\":\"stop\",\"logprobs\":{\"tokens\":[\"complete\"]}}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}",
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
    let result = @ai.generate_text(
      provider.completion("gpt-3.5-turbo-instruct"),
      prompt="MoonBit",
      top_k=5.0,
      provider_options={
        "openai": {
          "echo": true,
          "logitBias": { "42": -1 },
          "logprobs": 2,
          "user": "completion-user",
        },
      },
    )
    assert_eq(result.text(), " complete")
    assert_eq(result.usage.output_tokens.total, Some(1))
    assert_eq(result.warnings.length(), 1)
    assert_true(result.warnings[0] is @provider.Unsupported(feature="topK", ..))
    json_inspect(result.provider_metadata["openai"], content={
      "logprobs": { "tokens": ["complete"] },
    })
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
            assert_true(request_body.contains("\"quality\":\"high\""))
            assert_true(request_body.contains("\"output_format\":\"webp\""))
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
    let dalle = @ai.generate_image(provider.image("dall-e-3"), "Moon", n=2)
    let gpt_image = @ai.generate_image(
      provider.image_model("gpt-image-1"),
      "MoonBit",
      provider_options={
        "openai": { "quality": "high", "outputFormat": "webp" },
      },
    )
    assert_eq(dalle.images.length(), 2)
    assert_eq(dalle.usage.total_tokens, 4)
    assert_eq(gpt_image.images.length(), 1)
  }
}

///|
async test "official OpenAI completion model owns streaming decoding" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/completions")
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"stream\":true"))
          assert_true(request_body.contains("\"include_usage\":true"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"id\":\"cmpl_1\",\"model\":\"gpt-3.5-turbo-instruct\",\"choices\":[{\"text\":\"Moon\",\"finish_reason\":null,\"logprobs\":{\"tokens\":[\"Moon\"]}}]}\n\n",
          )
          connection.write(
            "data: {\"choices\":[{\"text\":\"Bit\",\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}\n\n",
          )
          connection.write("data: [DONE]\n\n")
        },
        max_connections=1,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let events : Array[@provider.LanguageModelV4StreamPart] = []
    let result = @ai.stream_text(
      provider.completion("gpt-3.5-turbo-instruct"),
      prompt="",
      on_event=event => events.push(event),
    )
    let text = StringBuilder::new()
    for event in events {
      match event {
        @provider.V4TextDelta(delta~, ..) => text.write_string(delta)
        _ => ()
      }
    }
    assert_eq(text.to_string(), "MoonBit")
    assert_eq(result.usage.output_tokens.total, Some(2))
    assert_eq(result.response.unwrap().id, Some("cmpl_1"))
    assert_true(events[0] is @provider.V4StreamStart(..))
    assert_true(
      events.any(event => event is @provider.V4TextDelta(delta="Moon", ..)),
    )
    json_inspect(result.provider_metadata["openai"], content={
      "logprobs": [{ "tokens": ["Moon"] }],
    })
  }
}

///|
async test "official OpenAI image edits use provider-owned multipart options" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/images/edits")
          assert_true(
            request.headers
            .get("content-type")
            .unwrap_or("")
            .contains("multipart/form-data; boundary="),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("name=\"image\""))
          assert_true(request_body.contains("name=\"mask\""))
          assert_true(request_body.contains("name=\"quality\"\r\n\r\nhigh"))
          assert_true(
            request_body.contains("name=\"input_fidelity\"\r\n\r\nhigh"),
          )
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"created\":1700000000,\"size\":\"1024x1024\",\"quality\":\"high\",\"output_format\":\"png\",\"data\":[{\"b64_json\":\"edited\",\"revised_prompt\":\"Revised\"}],\"usage\":{\"input_tokens\":2,\"output_tokens\":3,\"total_tokens\":5}}",
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
    let result = @ai.generate_image(
      provider.image("gpt-image-1"),
      "Edit",
      files=[
        @provider.ImageModelV4File::bytes(
          data=b"SOURCE",
          media_type="image/png",
        ),
      ],
      mask=@provider.ImageModelV4File::bytes(
        data=b"MASK",
        media_type="image/png",
      ),
      provider_options={
        "openai": { "quality": "high", "inputFidelity": "high" },
      },
    )
    assert_eq(result.images[0].data, @provider.ImageData::Base64("edited"))
    assert_eq(result.images[0].revised_prompt, Some("Revised"))
    assert_eq(result.usage.total_tokens, 5)
    json_inspect(result.provider_metadata["openai"], content={
      "images": [
        {
          "revisedPrompt": "Revised",
          "created": 1700000000,
          "size": "1024x1024",
          "quality": "high",
          "outputFormat": "png",
        },
      ],
    })
  }
}

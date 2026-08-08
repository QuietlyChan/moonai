///|
async fn bind_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
test "OpenAI public factory exposes the AI SDK provider contract" {
  let provider = createOpenAI(
    api_key="test-key",
    base_url="https://example.test/v1",
  )
  let generic_provider = provider as &@provider.ProviderV4
  assert_eq(generic_provider.specification_version(), "v4")
  let language_model = generic_provider.language_model("gpt-test")
  assert_eq(language_model.specification_version(), "v4")
  assert_eq(language_model.provider(), "openai.responses")
  assert_eq(language_model.model_id(), "gpt-test")
  let chat_model = provider.chat("gpt-chat-test")
  assert_eq(chat_model.provider(), "openai.chat")
  let completion_model = provider.completion("gpt-completion-test")
  assert_eq(completion_model.provider(), "openai.completion")
  let embedding_model = generic_provider.embedding_model("embedding-test")
  assert_eq(embedding_model.specification_version(), "v4")
  assert_eq(embedding_model.provider(), "openai.embedding")
  assert_eq(embedding_model.model_id(), "embedding-test")
  let image_model = generic_provider.image_model("gpt-image-test")
  assert_eq(image_model.specification_version(), "v4")
  assert_eq(image_model.provider(), "openai.image")
  assert_eq(image_model.model_id(), "gpt-image-test")
  let speech_model = generic_provider.speech_model("tts-test").unwrap()
  assert_eq(speech_model.specification_version(), "v4")
  assert_eq(speech_model.provider(), "openai.speech")
  let transcription_model = generic_provider
    .transcription_model("whisper-test")
    .unwrap()
  assert_eq(transcription_model.specification_version(), "v4")
  assert_eq(transcription_model.provider(), "openai.transcription")
  let files = generic_provider.files().unwrap()
  assert_eq(files.specification_version(), "v4")
  assert_eq(files.provider(), "openai.files")
  let skills = generic_provider.skills().unwrap()
  assert_eq(skills.specification_version(), "v4")
  assert_eq(skills.provider(), "openai.skills")
  assert_true(generic_provider.reranking_model("missing") is None)
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
async test "OpenAI Chat retries provider errors before output without leaking state" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          let attempt = request_count
          request_count = request_count + 1
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if attempt == 0 {
            connection.write(
              "data: {\"id\":\"chat-first\",\"model\":\"gpt-test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\n",
            )
            connection.write(
              "data: {\"error\":{\"message\":\"retry chat\",\"code\":\"insufficient_quota\"}}\n\n",
            )
          } else {
            connection.write(
              "data: {\"id\":\"chat-second\",\"model\":\"gpt-test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"retried\"},\"finish_reason\":\"stop\"}]}\n\n",
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
    let events : Array[@provider.LanguageModelV4StreamPart] = []
    let result = @ai.stream_text(
      provider.chat("gpt-test"),
      prompt="hello",
      include_raw_chunks=true,
      retry_policy=@provider.RetryPolicy::new(
        max_retries=1,
        initial_delay_ms=0,
        max_delay_ms=0,
      ),
      on_event=event => events.push(event),
    )
    assert_eq(request_count, 2)
    assert_eq(result.text(), "retried")
    assert_eq(result.response.unwrap().id, Some("chat-second"))
    let mut start_count = 0
    let mut leaked_first_attempt = false
    for event in events {
      match event {
        @provider.V4StreamStart(..) => start_count = start_count + 1
        @provider.V4Raw(value) if value.stringify().contains("chat-first") =>
          leaked_first_attempt = true
        _ => ()
      }
    }
    assert_eq(start_count, 1)
    assert_false(leaked_first_attempt)
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
            "data: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"resp-v4\",\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"},\"usage\":{\"input_tokens\":12,\"input_tokens_details\":{\"cached_tokens\":5,\"cache_write_tokens\":2},\"output_tokens\":9,\"output_tokens_details\":{\"reasoning_tokens\":3},\"total_tokens\":21}}}\n\n",
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
    assert_eq(result.usage.input_tokens.no_cache, Some(5))
    assert_eq(result.usage.input_tokens.cache_write, Some(2))
    assert_eq(result.usage.output_tokens.reasoning, Some(3))
    assert_eq(result.response.unwrap().id, Some("resp-v4"))
  }
}

///|
async test "OpenAI Responses V4 preserves item metadata on stream parts" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"store\":false"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-metadata\",\"model\":\"gpt-5\",\"created_at\":1700000020}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"rs_1\",\"type\":\"reasoning\",\"encrypted_content\":\"initial-encrypted\",\"summary\":[]}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.reasoning_summary_text.delta\",\"item_id\":\"rs_1\",\"summary_index\":0,\"delta\":\"plan\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.reasoning_summary_part.done\",\"item_id\":\"rs_1\",\"summary_index\":0}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"rs_1\",\"type\":\"reasoning\",\"encrypted_content\":\"final-encrypted\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"plan\"}]}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_item.added\",\"output_index\":1,\"item\":{\"id\":\"msg_1\",\"type\":\"message\",\"phase\":\"commentary\",\"content\":[]}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_text.annotation.added\",\"item_id\":\"msg_1\",\"annotation\":{\"type\":\"file_citation\",\"file_id\":\"file_1\",\"filename\":\"notes.txt\",\"index\":0}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"answer\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_text.done\",\"item_id\":\"msg_1\",\"text\":\"answer\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_item.done\",\"output_index\":1,\"item\":{\"id\":\"msg_1\",\"type\":\"message\",\"phase\":\"commentary\",\"content\":[]}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.output_item.added\",\"output_index\":2,\"item\":{\"id\":\"ws_1\",\"type\":\"web_search_call\",\"status\":\"in_progress\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-metadata\",\"status\":\"completed\",\"usage\":{\"input_tokens\":2,\"output_tokens\":3,\"total_tokens\":5}}}\n\n",
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
    ignore(
      @ai.stream_text(
        provider.responses("gpt-5"),
        prompt="hello",
        provider_options={ "openai": { "store": false } },
        on_event=event => events.push(event),
      ),
    )
    let mut saw_reasoning_start = false
    let mut saw_reasoning_delta = false
    let mut saw_reasoning_end = false
    let mut saw_text_start = false
    let mut saw_text_end = false
    let mut saw_hosted_tool_start = false
    let mut saw_raw = false
    for event in events {
      match event {
        @provider.V4ReasoningStart(provider_metadata~, ..) => {
          json_inspect(provider_metadata["openai"], content={
            "itemId": "rs_1",
            "reasoningEncryptedContent": "initial-encrypted",
          })
          saw_reasoning_start = true
        }
        @provider.V4ReasoningDelta(delta="plan", provider_metadata~, ..) => {
          json_inspect(provider_metadata["openai"], content={ "itemId": "rs_1" })
          saw_reasoning_delta = true
        }
        @provider.V4ReasoningEnd(provider_metadata~, ..) => {
          json_inspect(provider_metadata["openai"], content={
            "itemId": "rs_1",
            "reasoningEncryptedContent": "final-encrypted",
          })
          saw_reasoning_end = true
        }
        @provider.V4TextStart(provider_metadata~, ..) => {
          json_inspect(provider_metadata["openai"], content={
            "itemId": "msg_1",
            "phase": "commentary",
          })
          saw_text_start = true
        }
        @provider.V4TextEnd(provider_metadata~, ..) => {
          json_inspect(provider_metadata["openai"], content={
            "itemId": "msg_1",
            "phase": "commentary",
            "annotations": [
              {
                "type": "file_citation",
                "file_id": "file_1",
                "filename": "notes.txt",
                "index": 0,
              },
            ],
          })
          saw_text_end = true
        }
        @provider.V4ToolInputStart(id="ws_1", provider_executed=true, ..) =>
          saw_hosted_tool_start = true
        @provider.V4Raw(_) => saw_raw = true
        _ => ()
      }
    }
    assert_true(saw_reasoning_start)
    assert_true(saw_reasoning_delta)
    assert_true(saw_reasoning_end)
    assert_true(saw_text_start)
    assert_true(saw_text_end)
    assert_true(saw_hosted_tool_start)
    assert_false(saw_raw)
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
        status_code=Some(429),
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
        status_code=Some(503),
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
      @provider.APICallError(
        message~,
        status_code=Some(400),
        is_retryable=false,
        ..
      ) => assert_true(message.contains("Chat Completions"))
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
    assert_true(
      events.any(event => {
        match event {
          @provider.V4Error(error) =>
            error.message == "late failure" &&
            error.data is Some({ "type": "error", .. })
          _ => false
        }
      }),
    )
  }
}

///|
async test "OpenAI Responses maps errors flushed with acceptance to APICallError" {
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
            "data: {\"type\":\"response.in_progress\",\"response\":{\"id\":\"resp-accepted\",\"status\":\"in_progress\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"error\",\"error\":{\"message\":\"failure flushed with acceptance\",\"code\":\"server_error\"}}\n\n",
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
    try
      @ai.stream_text(
        provider.responses("responses-model"),
        prompt="hello",
        retry_policy=@provider.RetryPolicy::none(),
        on_event=event => events.push(event),
      )
      |> ignore
    catch {
      @provider.APICallError(
        message="failure flushed with acceptance",
        status_code=Some(500),
        is_retryable=true,
        ..
      ) => ()
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected the flushed provider error to fail the call")
    }
    assert_eq(events.length(), 0)
  }
}

///|
async test "OpenAI Responses keeps post-acceptance errors in the stream" {
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
            "data: {\"type\":\"response.in_progress\",\"response\":{\"id\":\"resp-accepted\",\"status\":\"in_progress\"}}\n\n",
          )
          connection.flush()
          @async.sleep(150)
          connection.write(
            "data: {\"type\":\"error\",\"error\":{\"message\":\"failure after acceptance\",\"code\":\"server_error\"}}\n\n",
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
    assert_eq(result.finish_reason.unified, @provider.V4FinishError)
    assert_true(
      events.any(event => {
        match event {
          @provider.V4Error(error) =>
            error.message == "failure after acceptance" &&
            error.data is Some({ "type": "error", .. })
          _ => false
        }
      }),
    )
  }
}

///|
async test "OpenAI Responses retries before acceptance without leaking decoder state" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          let attempt = request_count
          request_count = request_count + 1
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if attempt == 0 {
            connection.write(
              "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-first\",\"status\":\"queued\"}}\n\n",
            )
            connection.write(
              "data: {\"type\":\"error\",\"error\":{\"message\":\"retry first attempt\",\"code\":\"server_error\"}}\n\n",
            )
          } else {
            connection.write(
              "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-second\",\"status\":\"queued\"}}\n\n",
            )
            connection.write(
              "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_2\",\"delta\":\"retried\"}\n\n",
            )
            connection.write(
              "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-second\",\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n",
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
    let events : Array[@provider.LanguageModelV4StreamPart] = []
    let text = StringBuilder::new()
    let result = @ai.stream_text(
      provider.responses("responses-model"),
      prompt="hello",
      include_raw_chunks=true,
      retry_policy=@provider.RetryPolicy::new(
        max_retries=1,
        initial_delay_ms=0,
        max_delay_ms=0,
      ),
      on_event=event => {
        events.push(event)
        match event {
          @provider.V4TextDelta(delta~, ..) => text.write_string(delta)
          _ => ()
        }
      },
    )
    assert_eq(request_count, 2)
    assert_eq(text.to_string(), "retried")
    assert_eq(result.response.unwrap().id, Some("resp-second"))
    json_inspect(result.provider_metadata["openai"], content={
      "responseId": "resp-second",
    })
    let mut start_count = 0
    let mut leaked_first_attempt = false
    for event in events {
      match event {
        @provider.V4StreamStart(..) => start_count = start_count + 1
        @provider.V4Raw(value) if value.stringify().contains("resp-first") =>
          leaked_first_attempt = true
        _ => ()
      }
    }
    assert_eq(start_count, 1)
    assert_false(leaked_first_attempt)
  }
}

///|
async test "OpenAI Responses continues normally after acceptance" {
  @async.with_task_group() <| group => {
    let server = bind_test_server()
    let output_sent = Ref(false)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"response.in_progress\",\"response\":{\"id\":\"resp-accepted\",\"status\":\"in_progress\"}}\n\n",
          )
          connection.flush()
          @async.sleep(150)
          output_sent.val = true
          connection.write(
            "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"accepted\"}\n\n",
          )
          connection.write(
            "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-accepted\",\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n",
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
    let text = StringBuilder::new()
    let started_before_output = Ref(false)
    let result = @ai.stream_text(
      provider.responses("responses-model"),
      prompt="hello",
      retry_policy=@provider.RetryPolicy::none(),
      on_event=event => {
        events.push(event)
        match event {
          @provider.V4StreamStart(..) =>
            started_before_output.val = !output_sent.val
          @provider.V4TextDelta(delta~, ..) => text.write_string(delta)
          _ => ()
        }
      },
    )
    assert_eq(text.to_string(), "accepted")
    assert_true(started_before_output.val)
    assert_eq(result.finish_reason.unified, @provider.V4FinishStop)
    assert_true(
      events.any(event => event is @provider.V4TextDelta(delta="accepted", ..)),
    )
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
    assert_eq(dalle.response.unwrap().model_id, Some("dall-e-3"))
    assert_true(dalle.response.unwrap().created_at is Some(_))
    assert_eq(gpt_image.images.length(), 1)
    assert_eq(gpt_image.response.unwrap().model_id, Some("gpt-image-1"))
    assert_true(gpt_image.response.unwrap().created_at is Some(_))
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
      top_k=5.0,
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
    match events[0] {
      @provider.V4StreamStart(warnings~) => {
        assert_eq(warnings.length(), 1)
        assert_true(warnings[0] is @provider.Unsupported(feature="topK", ..))
      }
      _ => fail("expected the V4 stream-start event first")
    }
    assert_true(
      events.any(event => {
        event is @provider.V4TextDelta(id="0", delta="Moon", ..)
      }),
    )
    json_inspect(result.provider_metadata["openai"], content={
      "logprobs": { "tokens": ["Moon"] },
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

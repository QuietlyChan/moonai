///|
async fn bind_v4_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
}

///|
fn mark_anthropic_request_body(
  body : Json,
  betas : Array[String],
  mode : String,
) -> Json {
  guard body is Object(fields) else { return body }
  let transformed = @provider.copy_provider_metadata(fields)
  transformed["transformed_mode"] = Json::string(
    if betas.contains("provider-transform-beta") {
      mode
    } else {
      "missing-beta"
    },
  )
  Json::object(transformed)
}

///|
async test "Anthropic native V4 generate preserves provider usage and finish metadata" {
  @async.with_task_group() <| group => {
    let server = bind_v4_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"messages\""))
          assert_false(request_body.contains("\"stream\":true"))
          assert_true(
            request_body.contains("\"transformed_mode\":\"generate\""),
          )
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
            "x-request-id": "anthropic-v4-generate",
          })
          connection.write(
            "{\"type\":\"message\",\"id\":\"msg-v4-generate\",\"model\":\"claude-sonnet-4-6\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"plan\",\"signature\":\"sig\"},{\"type\":\"text\",\"text\":\"answer\"}],\"stop_reason\":\"max_tokens\",\"provider_metadata\":{\"anthropic.messages\":{\"trace_id\":\"generate-1\"}},\"usage\":{\"input_tokens\":10,\"cache_creation_input_tokens\":3,\"cache_read_input_tokens\":4,\"output_tokens\":6,\"output_tokens_details\":{\"thinking_tokens\":2}}}",
          )
        },
        max_connections=1,
      )
    }
    let model = @anthropic.anthropic(
      "claude-sonnet-4-6",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
      beta_features=["provider-transform-beta"],
      transform_request_body=(body, betas) => {
        mark_anthropic_request_body(body, betas, "generate")
      },
    )
    let result = model.do_generate(
      @provider.LanguageModelV4CallOptions::new(
        @provider.LanguageModelV4Prompt::new([
          @provider.V4UserMessage(
            content=[
              @provider.V4PromptText(text="hello", provider_options=Map([])),
            ],
            provider_options=Map([]),
          ),
        ]),
        frequency_penalty=0.5,
        max_output_tokens=128,
      ),
    )
    assert_eq(result.content.length(), 2)
    assert_eq(result.finish_reason.unified, @provider.V4FinishLength)
    assert_eq(result.finish_reason.raw, Some("max_tokens"))
    assert_eq(result.usage.input_tokens.total, Some(17))
    assert_eq(result.usage.input_tokens.no_cache, Some(10))
    assert_eq(result.usage.input_tokens.cache_read, Some(4))
    assert_eq(result.usage.input_tokens.cache_write, Some(3))
    assert_eq(result.usage.output_tokens.total, Some(6))
    assert_eq(result.usage.output_tokens.text, Some(4))
    assert_eq(result.usage.output_tokens.reasoning, Some(2))
    json_inspect(result.usage.raw.unwrap(), content={
      "input_tokens": 10,
      "cache_creation_input_tokens": 3,
      "cache_read_input_tokens": 4,
      "output_tokens": 6,
      "output_tokens_details": { "thinking_tokens": 2 },
    })
    match result.provider_metadata["anthropic.messages"] {
      {
        "trace_id": String(trace_id),
        "usage": {
          "input_tokens": Number(input, ..),
          "output_tokens": Number(output, ..),
          ..
        },
        ..
      } => {
        assert_eq(trace_id, "generate-1")
        assert_eq(input.to_int(), 10)
        assert_eq(output.to_int(), 6)
      }
      _ => fail("expected Anthropic V4 provider metadata")
    }
    assert_true(
      result.warnings.any(warning => {
        warning is @provider.Unsupported(feature="frequencyPenalty", ..)
      }),
    )
    match result.response {
      Some(metadata) => {
        assert_eq(metadata.id, Some("msg-v4-generate"))
        assert_eq(metadata.model_id, Some("claude-sonnet-4-6"))
        assert_eq(metadata.status_code, Some(200))
      }
      None => fail("expected Anthropic V4 response metadata")
    }
  }
}

///|
async test "Anthropic native V4 stream emits one warning batch and lossless finish" {
  @async.with_task_group() <| group => {
    let server = bind_v4_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"stream\":true"))
          assert_true(request_body.contains("\"transformed_mode\":\"stream\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
            "x-request-id": "anthropic-v4-stream",
          })
          connection.write(
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-v4-stream\",\"model\":\"claude-sonnet-4-6\",\"provider_metadata\":{\"anthropic.messages\":{\"trace_id\":\"stream-1\"}},\"usage\":{\"input_tokens\":8,\"cache_read_input_tokens\":2}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"streamed\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
          )
          connection.write(
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5,\"cache_creation_input_tokens\":1,\"output_tokens_details\":{\"thinking_tokens\":1}}}\n\n",
          )
          connection.write("data: {\"type\":\"message_stop\"}\n\n")
        },
        max_connections=1,
      )
    }
    let model = @anthropic.anthropic(
      "claude-sonnet-4-6",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
      beta_features=["provider-transform-beta"],
      transform_request_body=(body, betas) => {
        mark_anthropic_request_body(body, betas, "stream")
      },
    )
    let mut starts = 0
    let deltas : Array[String] = []
    let mut finishes = 0
    let terminal_metadata : Ref[Map[String, Json]] = Ref(Map([]))
    let result = model.do_stream(
      @provider.LanguageModelV4CallOptions::new(
        @provider.LanguageModelV4Prompt::new([
          @provider.V4UserMessage(
            content=[
              @provider.V4PromptText(text="hello", provider_options=Map([])),
            ],
            provider_options=Map([]),
          ),
        ]),
        frequency_penalty=0.5,
        max_output_tokens=128,
      ),
      event => {
        match event {
          @provider.V4StreamStart(warnings~) => {
            starts = starts + 1
            assert_true(
              warnings.any(warning => {
                warning is @provider.Unsupported(feature="frequencyPenalty", ..)
              }),
            )
          }
          @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
          @provider.V4Finish(usage~, reason~, provider_metadata~) => {
            finishes = finishes + 1
            terminal_metadata.val = @provider.copy_provider_metadata(
              provider_metadata,
            )
            assert_eq(usage.input_tokens.total, Some(11))
            assert_eq(usage.input_tokens.cache_read, Some(2))
            assert_eq(usage.input_tokens.cache_write, Some(1))
            assert_eq(usage.output_tokens.reasoning, Some(1))
            assert_eq(reason.unified, @provider.V4FinishStop)
            assert_eq(reason.raw, Some("end_turn"))
          }
          _ => ()
        }
      },
    )
    assert_eq(starts, 1)
    assert_eq(finishes, 1)
    assert_eq(deltas, ["streamed"])
    assert_true(result.request is Some(_))
    assert_eq(result.response.unwrap().id, Some("msg-v4-stream"))
    match terminal_metadata.val["anthropic.messages"] {
      {
        "trace_id": String(trace_id),
        "usage": {
          "input_tokens": Number(input, ..),
          "output_tokens": Number(output, ..),
          ..
        },
        ..
      } => {
        assert_eq(trace_id, "stream-1")
        assert_eq(input.to_int(), 8)
        assert_eq(output.to_int(), 5)
      }
      _ => fail("expected Anthropic V4 stream metadata")
    }
  }
}

///|
async test "Anthropic V4 HTTP stream continues after a malformed chunk" {
  @async.with_task_group() <| group => {
    let server = bind_v4_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-malformed-stream\",\"model\":\"claude-sonnet-4-6\",\"usage\":{\"input_tokens\":3}}}\n\n",
          )
          connection.write("data: {\"type\":\n\n")
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"recovered\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
          )
          connection.write(
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":2}}\n\n",
          )
          connection.write("data: {\"type\":\"message_stop\"}\n\n")
        },
        max_connections=1,
      )
    }
    let model = @anthropic.anthropic(
      "claude-sonnet-4-6",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let observed : Array[String] = []
    let mut errors = 0
    let result = model.do_stream(
      @provider.LanguageModelV4CallOptions::new(
        @provider.LanguageModelV4Prompt::new([
          @provider.V4UserMessage(
            content=[
              @provider.V4PromptText(text="hello", provider_options=Map([])),
            ],
            provider_options=Map([]),
          ),
        ]),
        include_raw_chunks=true,
      ),
      event => {
        match event {
          @provider.V4Raw(String(value)) if value == "{\"type\":" =>
            observed.push("raw-invalid")
          @provider.V4Error(error) => {
            errors = errors + 1
            assert_true(error.message.contains("Anthropic stream decode error"))
            observed.push("error")
          }
          @provider.V4TextDelta(delta="recovered", ..) => observed.push("text")
          @provider.V4Finish(reason~, ..) => {
            assert_eq(reason.unified, @provider.V4FinishStop)
            observed.push("finish")
          }
          _ => ()
        }
      },
    )
    assert_eq(errors, 1)
    assert_eq(observed, ["raw-invalid", "error", "text", "finish"])
    assert_eq(result.response.unwrap().id, Some("msg-malformed-stream"))
  }
}

///|
fn anthropic_metadata_test_options(
  provider_options : Map[String, Json],
) -> @provider.LanguageModelV4CallOptions {
  @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    max_output_tokens=64,
    provider_options~,
  )
}

///|
async fn collect_anthropic_v4_stream_metadata(
  model : &@provider.LanguageModelV4,
  options : @provider.LanguageModelV4CallOptions,
) -> Map[String, Json] {
  let metadata : Ref[Map[String, Json]] = Ref(Map([]))
  ignore(
    model.do_stream(options, event => {
      match event {
        @provider.V4Finish(provider_metadata~, ..) =>
          metadata.val = @provider.copy_provider_metadata(provider_metadata)
        _ => ()
      }
    }),
  )
  metadata.val
}

///|
async test "Anthropic V4 generate exposes custom metadata only for a used custom options key" {
  @async.with_task_group() <| group => {
    let server = bind_v4_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"type\":\"message\",\"id\":\"msg-custom-metadata\",\"model\":\"claude-sonnet-4-6\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"plan\",\"signature\":\"sig\"},{\"type\":\"text\",\"text\":\"answer\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2}}",
          )
        },
        max_connections=3,
      )
    }
    let model = create_anthropic(
        api_key="test-key",
        provider_name="my-custom-anthropic.messages",
        base_url="http://127.0.0.1:\{server.addr.port()}/v1",
        idle_timeout_ms=2_000,
      ).messages("claude-sonnet-4-6")
      as &@provider.LanguageModelV4
    let canonical = model.do_generate(
      anthropic_metadata_test_options({ "anthropic": { "sendReasoning": true } }),
    )
    assert_eq(canonical.provider_metadata.length(), 1)
    assert_true(canonical.provider_metadata.get("anthropic") is Some(_))
    match canonical.content[0] {
      @provider.V4ReasoningOutput(value) => {
        assert_eq(value.provider_metadata.length(), 1)
        assert_true(value.provider_metadata.get("anthropic") is Some(_))
      }
      _ => fail("expected reasoning content")
    }
    let custom = model.do_generate(
      anthropic_metadata_test_options({
        "my-custom-anthropic": { "sendReasoning": true },
      }),
    )
    assert_eq(custom.provider_metadata.length(), 2)
    assert_true(custom.provider_metadata.get("anthropic") is Some(_))
    assert_true(custom.provider_metadata.get("my-custom-anthropic") is Some(_))
    match custom.content[0] {
      @provider.V4ReasoningOutput(value) => {
        assert_eq(value.provider_metadata.length(), 2)
        assert_true(value.provider_metadata.get("anthropic") is Some(_))
        assert_true(
          value.provider_metadata.get("my-custom-anthropic") is Some(_),
        )
      }
      _ => fail("expected reasoning content")
    }
    let fallback = model.do_generate(anthropic_metadata_test_options(Map([])))
    assert_eq(fallback.provider_metadata.length(), 1)
    assert_true(fallback.provider_metadata.get("anthropic") is Some(_))
  }
}

///|
async test "Anthropic V4 stream exposes custom metadata only for a used custom options key" {
  @async.with_task_group() <| group => {
    let server = bind_v4_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-custom-stream\",\"model\":\"claude-sonnet-4-6\",\"usage\":{\"input_tokens\":1}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":2}}\n\n",
          )
          connection.write("data: {\"type\":\"message_stop\"}\n\n")
        },
        max_connections=3,
      )
    }
    let model = create_anthropic(
        api_key="test-key",
        provider_name="my-custom-anthropic.messages",
        base_url="http://127.0.0.1:\{server.addr.port()}/v1",
        idle_timeout_ms=2_000,
      ).messages("claude-sonnet-4-6")
      as &@provider.LanguageModelV4
    let canonical = collect_anthropic_v4_stream_metadata(
      model,
      anthropic_metadata_test_options({ "anthropic": { "sendReasoning": true } }),
    )
    assert_eq(canonical.length(), 1)
    assert_true(canonical.get("anthropic") is Some(_))
    let custom = collect_anthropic_v4_stream_metadata(
      model,
      anthropic_metadata_test_options({
        "my-custom-anthropic": { "sendReasoning": true },
      }),
    )
    assert_eq(custom.length(), 2)
    assert_true(custom.get("anthropic") is Some(_))
    assert_true(custom.get("my-custom-anthropic") is Some(_))
    let fallback = collect_anthropic_v4_stream_metadata(
      model,
      anthropic_metadata_test_options(Map([])),
    )
    assert_eq(fallback.length(), 1)
    assert_true(fallback.get("anthropic") is Some(_))
  }
}

///|
async test "Anthropic V4 stream preserves provider metadata on content lifecycle parts" {
  @async.with_task_group() <| group => {
    let server = bind_v4_test_server()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let _ = body.read_all()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          connection.write(
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-v4-content-metadata\",\"model\":\"claude-sonnet-4-6\",\"usage\":{\"input_tokens\":2}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\",\"signature\":\"\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"plan\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"signature_delta\",\"signature\":\"sig-part\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"redacted_thinking\",\"data\":\"secret-data\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"compaction\",\"content\":\"\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":2,\"delta\":{\"type\":\"compaction_delta\",\"content\":\"summary\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":2}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":3,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":3,\"delta\":{\"type\":\"citations_delta\",\"citation\":{\"type\":\"web_search_result_location\",\"url\":\"https://example.com/source\",\"title\":\"Source\",\"cited_text\":\"quoted\",\"encrypted_index\":\"enc\"}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_delta\",\"index\":3,\"delta\":{\"type\":\"text_delta\",\"text\":\"answer\"}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":3}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_start\",\"index\":4,\"content_block\":{\"type\":\"server_tool_use\",\"id\":\"srv-1\",\"name\":\"web_search\",\"input\":{\"query\":\"MoonBit\"}}}\n\n",
          )
          connection.write(
            "data: {\"type\":\"content_block_stop\",\"index\":4}\n\n",
          )
          connection.write(
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":4}}\n\n",
          )
          connection.write("data: {\"type\":\"message_stop\"}\n\n")
        },
        max_connections=1,
      )
    }
    let model = @anthropic.anthropic(
      "claude-sonnet-4-6",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
      id_generator=() => "source-id",
    )
    let events : Array[@provider.LanguageModelV4StreamPart] = []
    ignore(
      model.do_stream(anthropic_metadata_test_options(Map([])), event => {
        events.push(event)
      }),
    )
    let mut saw_signature = false
    let mut saw_redacted = false
    let mut saw_compaction = false
    let mut saw_citations = false
    let mut saw_server_tool_start = false
    let mut saw_raw = false
    for event in events {
      match event {
        @provider.V4ReasoningDelta(delta="", provider_metadata~, ..) => {
          json_inspect(provider_metadata["anthropic"], content={
            "signature": "sig-part",
          })
          saw_signature = true
        }
        @provider.V4ReasoningStart(provider_metadata~, ..) if provider_metadata.length() >
          0 => {
          json_inspect(provider_metadata["anthropic"], content={
            "redactedData": "secret-data",
          })
          saw_redacted = true
        }
        @provider.V4TextStart(provider_metadata~, ..) if provider_metadata.length() >
          0 => {
          json_inspect(provider_metadata["anthropic"], content={
            "type": "compaction",
          })
          saw_compaction = true
        }
        @provider.V4TextEnd(provider_metadata~, ..) if provider_metadata.length() >
          0 => {
          json_inspect(provider_metadata["anthropic"], content={
            "citations": [
              {
                "type": "web_search_result_location",
                "url": "https://example.com/source",
                "title": "Source",
                "cited_text": "quoted",
                "encrypted_index": "enc",
              },
            ],
          })
          saw_citations = true
        }
        @provider.V4ToolInputStart(id="srv-1", provider_executed=true, ..) =>
          saw_server_tool_start = true
        @provider.V4Raw(_) => saw_raw = true
        _ => ()
      }
    }
    assert_true(saw_signature)
    assert_true(saw_redacted)
    assert_true(saw_compaction)
    assert_true(saw_citations)
    assert_true(saw_server_tool_start)
    assert_false(saw_raw)
  }
}

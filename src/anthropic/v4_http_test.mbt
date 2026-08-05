///|
async fn bind_v4_test_server() -> @http.Server {
  @http.Server(@socket.Addr::parse("127.0.0.1:0"))
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
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
            "x-request-id": "anthropic-v4-generate",
          })
          connection.write(
            "{\"id\":\"msg-v4-generate\",\"model\":\"claude-sonnet-4-6\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"plan\",\"signature\":\"sig\"},{\"type\":\"text\",\"text\":\"answer\"}],\"stop_reason\":\"max_tokens\",\"provider_metadata\":{\"anthropic.messages\":{\"trace_id\":\"generate-1\"}},\"usage\":{\"input_tokens\":10,\"cache_creation_input_tokens\":3,\"cache_read_input_tokens\":4,\"output_tokens\":6,\"output_tokens_details\":{\"thinking_tokens\":2}}}",
          )
        },
        max_connections=1,
      )
    }
    let model = AnthropicLanguageModelV4::new(
        @anthropic.anthropic_messages(
          "claude-sonnet-4-6",
          api_key="test-key",
          base_url="http://127.0.0.1:\{server.addr.port()}/v1",
          idle_timeout_ms=2_000,
        ),
      )
      as &@provider.LanguageModelV4
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
        (_request, _body, connection) => {
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
    let model = AnthropicLanguageModelV4::new(
        @anthropic.anthropic_messages(
          "claude-sonnet-4-6",
          api_key="test-key",
          base_url="http://127.0.0.1:\{server.addr.port()}/v1",
          idle_timeout_ms=2_000,
        ),
      )
      as &@provider.LanguageModelV4
    let mut starts = 0
    let mut warnings = 0
    let deltas : Array[String] = []
    let mut finishes = 0
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
          @provider.V4Warning(_) => warnings = warnings + 1
          @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
          @provider.V4Finish(usage~, reason~, ..) => {
            finishes = finishes + 1
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
    assert_eq(warnings, 0)
    assert_eq(finishes, 1)
    assert_eq(deltas, ["streamed"])
    assert_eq(result.usage.input_tokens.total, Some(11))
    assert_eq(result.usage.input_tokens.no_cache, Some(8))
    assert_eq(result.usage.output_tokens.total, Some(5))
    assert_eq(result.usage.output_tokens.text, Some(4))
    assert_eq(result.finish_reason.unified, @provider.V4FinishStop)
    assert_eq(result.finish_reason.raw, Some("end_turn"))
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
        assert_eq(trace_id, "stream-1")
        assert_eq(input.to_int(), 8)
        assert_eq(output.to_int(), 5)
      }
      _ => fail("expected Anthropic V4 stream metadata")
    }
  }
}

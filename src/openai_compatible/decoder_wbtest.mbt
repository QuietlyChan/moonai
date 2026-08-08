///|
fn compatible_test_stream_decoder(
  include_raw_chunks? : Bool = false,
  provider_name? : String = "",
  metadata_key? : String = "",
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : OpenAICompatibleUsageConverter = convert_openai_compatible_chat_usage,
  id_generator? : @provider_utils.IdGenerator = @provider_utils.generate_id,
  generate_reasoning_ids? : Bool = false,
  text_stream_id? : String = "txt-0",
  close_text_before_reasoning? : Bool = false,
  close_text_before_tool_calls? : Bool = false,
  validate_stream_chunk? : OpenAICompatibleJsonValidator = validate_openai_compatible_chat_chunk,
) -> OpenAICompatibleStreamDecoder {
  OpenAICompatibleStreamDecoder::new(
    include_raw_chunks, provider_name, metadata_key, error_structure, metadata_extractor,
    convert_usage, id_generator, generate_reasoning_ids, text_stream_id, close_text_before_reasoning,
    close_text_before_tool_calls, validate_stream_chunk,
  )
}

///|
fn decode_compatible_test_response(
  json : Json,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  convert_usage? : OpenAICompatibleUsageConverter = convert_openai_compatible_chat_usage,
  metadata_key? : String = "openai-compatible",
  id_generator? : @provider_utils.IdGenerator = @provider_utils.generate_id,
  validate_response? : OpenAICompatibleJsonValidator = validate_openai_compatible_chat_response,
) -> @provider.ChatResponse raise {
  let decoded = decode_chat_response(
    json, error_structure, convert_usage, metadata_key, id_generator, validate_response,
  )
  @provider.ChatResponse::from_content(
    @provider.LanguageModelV4Content::to_generated_content_array(
      decoded.content,
    ),
    decoded.usage.to_usage(),
    match decoded.finish_reason {
      { unified: @provider.V4FinishOther, raw: None } => @provider.Unknown("")
      reason => reason.to_finish_reason()
    },
  ).with_diagnostics(None, decoded.response, decoded.provider_metadata, [])
}

///|
test "decode the public OpenAI-compatible error data shape" {
  let decoded = decode_openai_compatible_error_data({
    "error": {
      "message": "quota exceeded",
      "type": "rate_limit",
      "param": "tokens",
      "code": 429,
    },
  }).unwrap()
  assert_eq(decoded.error.message, "quota exceeded")
  assert_eq(decoded.error.error_type, Some("rate_limit"))
  assert_eq(decoded.error.param, Some("tokens"))
  assert_eq(decoded.error.code, Some(429))
}

///|
test "stream usage converters receive omitted usage as None" {
  let decoder = compatible_test_stream_decoder(convert_usage=usage => {
    match usage {
      None =>
        {
          input_tokens: {
            total: Some(41),
            no_cache: Some(41),
            cache_read: None,
            cache_write: None,
          },
          output_tokens: { total: Some(1), text: Some(1), reasoning: None },
          raw: None,
        }
      Some(raw) => @provider.LanguageModelV4Usage::unknown().with_raw(Some(raw))
    }
  })
  assert_eq(decoder.v4_usage().input_tokens.total, Some(41))
  assert_eq(decoder.v4_usage().output_tokens.total, Some(1))
}

///|
async test "golden SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/openai_compatible/testdata/tool_calls.sse").text()
  let decoder = compatible_test_stream_decoder()
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  for line in fixture.split("\n") {
    let batch = decoder.feed_line(line.to_owned())
    for event in batch.events {
      events.push(event)
    }
  }
  assert_eq(decoder.text.to_string(), "It is sunny.")
  assert_eq(decoder.reasoning.to_string(), "checking tools")
  assert_eq(decoder.tools.calls(), [
    @provider.ToolCall::new(
      id="call_weather",
      name="get_weather",
      arguments="{\"city\":\"Hangzhou\"}",
    ),
    @provider.ToolCall::new(
      id="call_time",
      name="get_time",
      arguments="{\"zone\":\"Asia/Shanghai\"}",
    ),
  ])
  assert_eq(decoder.v4_usage().to_usage(), {
    input_tokens: 12,
    output_tokens: 7,
    total_tokens: 19,
    reasoning_tokens: 2,
    cached_input_tokens: 3,
    cache_write_input_tokens: 0,
  })
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishToolCalls)
  let mut tool_ready = 0
  for event in events {
    if event is @provider.V4ToolCallReady(_) {
      tool_ready = tool_ready + 1
    }
  }
  assert_eq(tool_ready, 2)
}

///|
test "EOF after finish reason finalizes compatible streams" {
  let decoder = compatible_test_stream_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"hello\",\"reasoning\":\"think\"},\"finish_reason\":\"stop\"}]}",
  )
  let chunk = decoder.feed_line("")
  assert_eq(chunk.done, false)
  assert_false(decoder.flush_buffered().done)
  let terminal = decoder.finish_stream()
  assert_eq(terminal.done, true)
  assert_eq(decoder.text.to_string(), "hello")
  assert_eq(decoder.reasoning.to_string(), "think")
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishStop)
}

///|
test "normal EOF finalizes compatible streams without a finish reason" {
  let decoder = compatible_test_stream_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_false(chunk.done)
  assert_false(decoder.flush_buffered().done)
  let terminal = decoder.finish_stream()
  assert_true(terminal.done)
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishOther, raw: None },
        ..
      )
    }),
  )
}

///|
test "compatible stream emits reasoning before text from the same chunk" {
  let decoder = compatible_test_stream_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"think\",\"content\":\"answer\"},\"finish_reason\":\"stop\"}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(chunk.events[0] is @provider.V4ResponseMetadataReady(_))
  assert_true(chunk.events[1] is @provider.V4ReasoningStart(..))
  assert_true(chunk.events[2] is @provider.V4ReasoningDelta(..))
  assert_true(chunk.events[3] is @provider.V4ReasoningEnd(..))
  assert_true(chunk.events[4] is @provider.V4TextStart(id="txt-0", ..))
  assert_true(
    chunk.events[5] is @provider.V4TextDelta(id="txt-0", delta="answer", ..),
  )
}

///|
test "include_raw_chunks exposes parsed Chat Completions chunks" {
  let decoder = compatible_test_stream_decoder(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(chunk.events[0] is @provider.V4Raw(_))
  assert_true(chunk.events[1] is @provider.V4ResponseMetadataReady(_))
  assert_true(chunk.events[2] is @provider.V4TextStart(..))
  assert_true(chunk.events[3] is @provider.V4TextDelta(..))
}

///|
test "stream metadata extractors observe structured error chunks" {
  let observed = Ref(0)
  let metadata_extractor = OpenAICompatibleMetadataExtractor::new(
    extract_metadata=_ => Map([]),
    create_stream_extractor=() => {
      OpenAICompatibleStreamMetadataExtractor::new(
        process_chunk=_ => observed.val = observed.val + 1,
        build_metadata=() => {
          Map([("vendor", ({ "observed": observed.val } : Json))])
        },
      )
    },
  )
  let decoder = compatible_test_stream_decoder(metadata_extractor~)
  let _ = decoder.feed_line(
    "data: {\"error\":{\"message\":\"provider failed\",\"code\":\"failed\"}}",
  )
  let batch = decoder.feed_line("")
  assert_eq(observed.val, 1)
  assert_true(batch.events[0] is @provider.V4Error(_))
  json_inspect(decoder.provider_metadata_snapshot()["vendor"], content={
    "observed": 1,
  })
}

///|
test "stream error flushes an already-started partial tool call" {
  let decoder = compatible_test_stream_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\"}}]}}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"error\":{\"message\":\"provider failed\"}}",
  )
  let error_batch = decoder.feed_line("")
  assert_eq(error_batch.done, false)
  let mut errors = 0
  let mut ready = 0
  for event in error_batch.events {
    match event {
      @provider.V4Error(error) => {
        assert_eq(error.message, "provider failed")
        assert_true(error.data is Some({ "message": "provider failed", .. }))
        errors = errors + 1
      }
      @provider.V4ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(errors, 1)
  assert_eq(ready, 0)
  let terminal = decoder.finish_stream()
  assert_eq(terminal.done, true)
  for event in terminal.events {
    match event {
      @provider.V4ToolCallReady(_) => ready = ready + 1
      @provider.V4Finish(reason~, ..) => {
        assert_true(reason.unified is @provider.V4FinishError)
        assert_true(reason.raw is None)
      }
      _ => ()
    }
  }
  assert_eq(ready, 1)
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishError)
  assert_eq(decoder.tools.calls().length(), 1)
}

///|
test "decode non-streaming OpenAI-compatible result" {
  let response = decode_compatible_test_response({
    "choices": [
      {
        "message": {
          "role": "assistant",
          "content": "Calling tools.",
          "reasoning_content": "checking",
          "tool_calls": [
            {
              "id": "call_weather",
              "type": "function",
              "function": {
                "name": "get_weather",
                "arguments": "{\"city\":\"Hangzhou\"}",
              },
            },
            {
              "id": "call_time",
              "type": "function",
              "function": {
                "name": "get_time",
                "arguments": "{\"zone\":\"Asia/Shanghai\"}",
              },
            },
          ],
        },
        "finish_reason": "tool_calls",
      },
    ],
    "usage": {
      "prompt_tokens": 12,
      "completion_tokens": 7,
      "total_tokens": 19,
      "prompt_tokens_details": { "cached_tokens": 3, "cache_write_tokens": 2 },
      "completion_tokens_details": { "reasoning_tokens": 2 },
    },
  })
  assert_eq(response.text, "Calling tools.")
  assert_eq(response.reasoning, "checking")
  assert_eq(response.tool_calls, [
    @provider.ToolCall::new(
      id="call_weather",
      name="get_weather",
      arguments="{\"city\":\"Hangzhou\"}",
    ),
    @provider.ToolCall::new(
      id="call_time",
      name="get_time",
      arguments="{\"zone\":\"Asia/Shanghai\"}",
    ),
  ])
  assert_eq(response.usage, {
    input_tokens: 12,
    output_tokens: 7,
    total_tokens: 19,
    reasoning_tokens: 2,
    cached_input_tokens: 3,
    cache_write_input_tokens: 0,
  })
  assert_eq(response.finish_reason, @provider.ToolCalls)
}

///|
test "compatible decoders use injected ids for tools and Alibaba reasoning" {
  let response = decode_compatible_test_response(
    {
      "choices": [
        {
          "message": {
            "tool_calls": [
              { "function": { "name": "lookup", "arguments": "{}" } },
            ],
          },
          "finish_reason": "tool_calls",
        },
      ],
    },
    id_generator=() => "generated-tool-call",
  )
  assert_eq(response.tool_calls[0].id, "generated-tool-call")

  let decoder = compatible_test_stream_decoder(
    id_generator=() => "generated-reasoning",
    generate_reasoning_ids=true,
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"think\"},\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(
    chunk.events.any(event => {
      event is @provider.V4ReasoningStart(id="generated-reasoning", ..)
    }),
  )
  assert_true(
    chunk.events.any(event => {
      event
      is @provider.V4ReasoningDelta(id="generated-reasoning", delta="think", ..)
    }),
  )
}

///|
test "decode non-streaming error raises provider message" {
  try
    decode_compatible_test_response({
      "error": { "message": "bad request", "type": "invalid_request_error" },
    })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(
        message.contains("OpenAI-compatible request failed: bad request"),
      )
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected decode_compatible_test_response to raise")
  }
}

///|
test "decode non-streaming empty choices raises a protocol error" {
  try decode_compatible_test_response({ "choices": [] }) catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("no choices"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected empty choices to raise")
  }
}

///|
test "non-streaming compatible responses reject malformed tool calls" {
  try
    decode_compatible_test_response({
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              { "id": "call-1", "function": { "arguments": "{}" } },
            ],
          },
          "finish_reason": "tool_calls",
        },
      ],
    })
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("function.name"))
      assert_true(data is { "choices": Array(_), .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected malformed tool call to be rejected")
  }
}

///|
test "non-streaming compatible responses reject non-assistant messages" {
  try
    decode_compatible_test_response({
      "choices": [
        {
          "message": { "role": "user", "content": "unexpected" },
          "finish_reason": "stop",
        },
      ],
    })
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains(".role"))
      assert_true(data is { "choices": Array(_), .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected invalid response role to be rejected")
  }
}

///|
test "non-streaming compatible tool calls retain thought signatures and usage details" {
  let response = decode_compatible_test_response(
    {
      "id": "chat-1",
      "model": "gemini-compatible",
      "created": 1700000000,
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              {
                "id": "call-1",
                "type": "function",
                "function": { "name": "lookup", "arguments": "{}" },
                "extra_content": {
                  "google": { "thought_signature": "signature-1" },
                },
              },
            ],
          },
          "finish_reason": "function_call",
        },
      ],
      "usage": {
        "prompt_tokens": 2,
        "completion_tokens": 3,
        "total_tokens": 5,
        "completion_tokens_details": {
          "accepted_prediction_tokens": 7,
          "rejected_prediction_tokens": 2,
        },
      },
    },
    metadata_key="google",
  )
  assert_eq(response.finish_reason, @provider.ToolCalls)
  assert_eq(response.tool_calls, [
    @provider.ToolCall::new(id="call-1", name="lookup", arguments="{}", provider_metadata={
      "google": { "thoughtSignature": "signature-1" },
    }),
  ])
  json_inspect(response.provider_metadata["google"], content={
    "acceptedPredictionTokens": 7,
    "rejectedPredictionTokens": 2,
  })
  assert_eq(response.response.map(value => value.id), Some(Some("chat-1")))
}

///|
test "missing compatible finish reason remains other" {
  let response = decode_compatible_test_response({
    "choices": [{ "message": { "role": "assistant", "content": "partial" } }],
  })
  assert_eq(response.finish_reason, @provider.Unknown(""))
  assert_eq(response.provider_metadata.length(), 1)
  json_inspect(
    response.provider_metadata["openai-compatible"],
    content=Json::empty_object(),
  )
}

///|
test "compatible stream buffers tool arguments until the name arrives" {
  let decoder = compatible_test_stream_decoder(metadata_key="google")
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  let _ = decoder.feed_line(
    "data: {\"id\":\"stream-1\",\"model\":\"gemini-compatible\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"arguments\":\"{\\\"city\\\"\"},\"extra_content\":{\"google\":{\"thought_signature\":\"signature-1\"}}}]},\"finish_reason\":null}]}",
  )
  let first = decoder.feed_line("")
  for event in first.events {
    events.push(event)
    assert_true(!(event is @provider.V4ToolInputStart(..)))
  }
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"lookup\",\"arguments\":\":\\\"Hangzhou\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"completion_tokens_details\":{\"accepted_prediction_tokens\":4,\"rejected_prediction_tokens\":1}}}",
  )
  let second = decoder.feed_line("")
  for event in second.events {
    events.push(event)
  }
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  for event in terminal.events {
    events.push(event)
  }
  let mut metadata_events = 0
  let mut starts = 0
  let mut ready = 0
  for event in events {
    match event {
      @provider.V4ResponseMetadataReady(_) =>
        metadata_events = metadata_events + 1
      @provider.V4ToolInputStart(tool_name="lookup", ..) => starts = starts + 1
      @provider.V4ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(metadata_events, 1)
  assert_eq(starts, 1)
  assert_eq(ready, 1)
  assert_eq(decoder.tools.calls(), [
    @provider.ToolCall::new(
      id="call-1",
      name="lookup",
      arguments="{\"city\":\"Hangzhou\"}",
      provider_metadata={ "google": { "thoughtSignature": "signature-1" } },
    ),
  ])
  json_inspect(decoder.provider_metadata_snapshot()["google"], content={
    "acceptedPredictionTokens": 4,
    "rejectedPredictionTokens": 1,
  })
}

///|
test "compatible stream rejects a tool call that never receives a name" {
  let decoder = compatible_test_stream_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"arguments\":\"{}\"}}]},\"finish_reason\":null}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: [DONE]")
  try decoder.feed_line("") catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_eq(message, "Expected 'function.name' to be a string.")
      assert_true(data is { "index": 0, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed missing function.name error")
  }
}

///|
test "malformed compatible stream chunks become stream errors" {
  let decoder = compatible_test_stream_decoder(include_raw_chunks=true)
  let _ = decoder.feed_line("data: {not-json")
  let malformed = decoder.feed_line("")
  assert_eq(malformed.done, false)
  assert_true(malformed.events[0] is @provider.V4Raw(String("{not-json")))
  assert_true(malformed.events[1] is @provider.V4Error(_))
  let terminal = decoder.finish_stream()
  assert_eq(terminal.done, true)
  assert_true(
    terminal.events[0]
    is @provider.V4Finish(reason={ unified: @provider.V4FinishError, .. }, ..),
  )
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishError)
}

///|
test "schema-invalid compatible responses retain the rejected value" {
  try
    decode_compatible_test_response({
      "choices": [
        {
          "message": { "role": "assistant", "content": "answer" },
          "finish_reason": "stop",
        },
      ],
      "usage": { "prompt_tokens": "one" },
    })
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("usage.prompt_tokens"))
      assert_true(data is { "usage": { "prompt_tokens": "one", .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a schema-invalid compatible response")
  }
}

///|
test "schema-invalid compatible stream chunks emit raw then error" {
  let decoder = compatible_test_stream_decoder(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"choices\":\"not-an-array\",\"usage\":null}",
  )
  let invalid = decoder.feed_line("")
  assert_eq(invalid.events.length(), 2)
  assert_true(
    invalid.events[0] is @provider.V4Raw({ "choices": "not-an-array", .. }),
  )
  match invalid.events[1] {
    @provider.V4Error(error) => {
      assert_true(error.message.contains("choices array"))
      assert_true(error.data is Some({ "choices": "not-an-array", .. }))
    }
    _ => fail("expected schema error after raw compatible chunk")
  }
  let terminal = decoder.finish_stream()
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(reason={ unified: @provider.V4FinishError, .. }, ..)
    }),
  )
}

///|
test "negative compatible tool indexes retain the offending chunk" {
  let decoder = compatible_test_stream_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":-1,\"function\":{\"name\":\"lookup\"}}]}}]}",
  )
  try decoder.feed_line("") catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("non-negative"))
      assert_true(data is { "index": Number(value, ..), .. } && value == -1.0)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed tool-index response error")
  }
}

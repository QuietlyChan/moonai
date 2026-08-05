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
async test "golden SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/openai_compatible/testdata/tool_calls.sse").text()
  let decoder = OpenAICompatibleStreamDecoder::new()
  let events : Array[@provider.StreamEvent] = []
  for line in fixture.split("\n") {
    let batch = decoder.feed_line(line.to_owned())
    for event in batch.events {
      events.push(event)
    }
  }
  let response = decoder.response()
  assert_eq(response.text, "It is sunny.")
  assert_eq(response.reasoning, "checking tools")
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
  let mut tool_ready = 0
  for event in events {
    if event is @provider.ToolCallReady(_) {
      tool_ready = tool_ready + 1
    }
  }
  assert_eq(tool_ready, 2)
}

///|
test "EOF after finish reason finalizes compatible streams" {
  let decoder = OpenAICompatibleStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"hello\",\"reasoning\":\"think\"},\"finish_reason\":\"stop\"}]}",
  )
  let chunk = decoder.feed_line("")
  assert_eq(chunk.done, false)
  let terminal = decoder.flush_buffered()
  assert_eq(terminal.done, true)
  let response = decoder.response()
  assert_eq(response.text, "hello")
  assert_eq(response.reasoning, "think")
  assert_eq(response.finish_reason, @provider.Stop)
}

///|
test "compatible stream emits reasoning before text from the same chunk" {
  let decoder = OpenAICompatibleStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"think\",\"content\":\"answer\"},\"finish_reason\":\"stop\"}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(chunk.events[0] is @provider.ResponseMetadataReady(_))
  assert_true(chunk.events[1] is @provider.ReasoningStart(_))
  assert_true(chunk.events[2] is @provider.ReasoningDelta(..))
  assert_true(chunk.events[3] is @provider.ReasoningEnd(_))
  assert_true(chunk.events[4] is @provider.TextStart(_))
  assert_true(chunk.events[5] is @provider.TextDelta(..))
}

///|
test "include_raw_chunks exposes parsed Chat Completions chunks" {
  let decoder = OpenAICompatibleStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(chunk.events[0] is @provider.Raw(_))
  assert_true(chunk.events[1] is @provider.ResponseMetadataReady(_))
  assert_true(chunk.events[2] is @provider.TextStart(_))
  assert_true(chunk.events[3] is @provider.TextDelta(..))
}

///|
test "stream error produces error finish without partial tool call" {
  let decoder = OpenAICompatibleStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\"}}]}}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"error\":{\"message\":\"provider failed\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  let mut errors = 0
  let mut ready = 0
  for event in terminal.events {
    match event {
      @provider.StreamError("provider failed") => errors = errors + 1
      @provider.ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(errors, 1)
  assert_eq(ready, 0)
  assert_eq(decoder.response().finish_reason, @provider.Error)
  assert_eq(decoder.response().tool_calls.length(), 0)
}

///|
test "decode non-streaming OpenAI-compatible result" {
  let response = decode_chat_response({
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
    cache_write_input_tokens: 2,
  })
  assert_eq(response.finish_reason, @provider.ToolCalls)
}

///|
test "compatible decoders use injected ids for tools and Alibaba reasoning" {
  let response = decode_chat_response(
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

  let decoder = OpenAICompatibleStreamDecoder::new(
    id_generator=() => "generated-reasoning",
    generate_reasoning_ids=true,
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"think\"},\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(
    chunk.events.any(event => {
      event is @provider.ReasoningStart("generated-reasoning")
    }),
  )
  assert_true(
    chunk.events.any(event => {
      event is @provider.ReasoningDelta(id="generated-reasoning", delta="think")
    }),
  )
}

///|
test "decode non-streaming error raises provider message" {
  try
    decode_chat_response({
      "error": { "message": "bad request", "type": "invalid_request_error" },
    })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(
        message.contains("OpenAI-compatible request failed: bad request"),
      )
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected decode_chat_response to raise")
  }
}

///|
test "decode non-streaming empty choices raises a protocol error" {
  try decode_chat_response({ "choices": [] }) catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("no choices"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected empty choices to raise")
  }
}

///|
test "non-streaming compatible tool calls retain thought signatures and usage details" {
  let response = decode_chat_response(
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
  let response = decode_chat_response({
    "choices": [{ "message": { "role": "assistant", "content": "partial" } }],
  })
  assert_eq(response.finish_reason, @provider.Unknown(""))
  assert_eq(response.provider_metadata.length(), 0)
}

///|
test "compatible stream buffers tool arguments until the name arrives" {
  let decoder = OpenAICompatibleStreamDecoder::new(metadata_key="google")
  let events : Array[@provider.StreamEvent] = []
  let _ = decoder.feed_line(
    "data: {\"id\":\"stream-1\",\"model\":\"gemini-compatible\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"arguments\":\"{\\\"city\\\"\"},\"extra_content\":{\"google\":{\"thought_signature\":\"signature-1\"}}}]},\"finish_reason\":null}]}",
  )
  let first = decoder.feed_line("")
  for event in first.events {
    events.push(event)
    assert_true(!(event is @provider.ToolInputStart(..)))
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
      @provider.ResponseMetadataReady(_) =>
        metadata_events = metadata_events + 1
      @provider.ToolInputStart(tool_name="lookup", ..) => starts = starts + 1
      @provider.ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(metadata_events, 1)
  assert_eq(starts, 1)
  assert_eq(ready, 1)
  let response = decoder.response()
  assert_eq(response.tool_calls, [
    @provider.ToolCall::new(
      id="call-1",
      name="lookup",
      arguments="{\"city\":\"Hangzhou\"}",
      provider_metadata={ "google": { "thoughtSignature": "signature-1" } },
    ),
  ])
  json_inspect(response.provider_metadata["google"], content={
    "acceptedPredictionTokens": 4,
    "rejectedPredictionTokens": 1,
  })
}

///|
test "compatible stream reports a tool call that never receives a name" {
  let decoder = OpenAICompatibleStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"arguments\":\"{}\"}}]},\"finish_reason\":null}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_true(terminal.events[0] is @provider.StreamError(_))
  assert_true(
    terminal.events[1] is @provider.Finish(reason=@provider.Error, ..),
  )
  assert_eq(decoder.response().finish_reason, @provider.Error)
  assert_eq(decoder.response().tool_calls.length(), 0)
}

///|
test "malformed compatible stream chunks become stream errors" {
  let decoder = OpenAICompatibleStreamDecoder::new()
  let _ = decoder.feed_line("data: {not-json")
  let malformed = decoder.feed_line("")
  assert_eq(malformed.done, false)
  assert_true(malformed.events[0] is @provider.StreamError(_))
  let terminal = decoder.flush_buffered()
  assert_eq(terminal.done, true)
  assert_true(
    terminal.events[0] is @provider.Finish(reason=@provider.Error, ..),
  )
  assert_eq(decoder.response().finish_reason, @provider.Error)
}

///|
test "negative compatible tool indexes retain the offending chunk" {
  let decoder = OpenAICompatibleStreamDecoder::new()
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

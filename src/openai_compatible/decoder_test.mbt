///|
async test "golden SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/openai_compatible/testdata/tool_calls.sse").text()
  let decoder = OpenAICompatibleStreamDecoder::new()
  let events : Array[@moonai.StreamEvent] = []
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
    @moonai.ToolCall::new(
      id="call_weather",
      name="get_weather",
      arguments="{\"city\":\"Hangzhou\"}",
    ),
    @moonai.ToolCall::new(
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
  })
  assert_eq(response.finish_reason, @moonai.ToolCalls)
  let mut tool_ready = 0
  for event in events {
    if event is @moonai.ToolCallReady(_) {
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
  assert_eq(response.finish_reason, @moonai.Stop)
}

///|
test "include_raw_chunks exposes parsed Chat Completions chunks" {
  let decoder = OpenAICompatibleStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(chunk.events[0] is @moonai.Raw(_))
  assert_true(chunk.events[1] is @moonai.TextStart(_))
  assert_true(chunk.events[2] is @moonai.TextDelta(..))
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
      @moonai.StreamError("provider failed") => errors = errors + 1
      @moonai.ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(errors, 1)
  assert_eq(ready, 0)
  assert_eq(decoder.response().finish_reason, @moonai.Error)
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
      "prompt_tokens_details": { "cached_tokens": 3 },
      "completion_tokens_details": { "reasoning_tokens": 2 },
    },
  })
  assert_eq(response.text, "Calling tools.")
  assert_eq(response.reasoning, "checking")
  assert_eq(response.tool_calls, [
    @moonai.ToolCall::new(
      id="call_weather",
      name="get_weather",
      arguments="{\"city\":\"Hangzhou\"}",
    ),
    @moonai.ToolCall::new(
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
  })
  assert_eq(response.finish_reason, @moonai.ToolCalls)
}

///|
test "decode non-streaming error raises provider message" {
  try
    decode_chat_response({
      "error": { "message": "bad request", "type": "invalid_request_error" },
    })
  catch {
    Failure::Failure(message) =>
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
    Failure::Failure(message) => assert_true(message.contains("no choices"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected empty choices to raise")
  }
}

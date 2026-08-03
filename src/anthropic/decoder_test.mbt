///|
async test "golden Anthropic SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/anthropic/testdata/messages.sse").text()
  let decoder = AnthropicStreamDecoder::new()
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
    input_tokens: 17,
    output_tokens: 7,
    total_tokens: 24,
    reasoning_tokens: 2,
    cached_input_tokens: 3,
  })
  assert_eq(response.finish_reason, @moonai.ToolCalls)
  let mut tool_ready = 0
  let mut tool_delta = 0
  let mut finish = 0
  let mut text_delta = 0
  let mut reasoning_delta = 0
  for event in events {
    match event {
      @moonai.ToolCallReady(_) => tool_ready = tool_ready + 1
      @moonai.ToolInputDelta(..) => tool_delta = tool_delta + 1
      @moonai.Finish(..) => finish = finish + 1
      @moonai.TextDelta(..) => text_delta = text_delta + 1
      @moonai.ReasoningDelta(..) => reasoning_delta = reasoning_delta + 1
      _ => ()
    }
  }
  assert_eq(tool_ready, 2)
  assert_eq(tool_delta, 4)
  assert_eq(text_delta, 1)
  assert_eq(reasoning_delta, 1)
  assert_eq(finish, 1)
}

///|
test "Anthropic decoder flushes a final unterminated event" {
  let decoder = AnthropicStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}",
  )
  let batch = decoder.flush_buffered()
  assert_true(batch.consumed_event)
  assert_eq(decoder.response().text, "partial")
}

///|
test "Anthropic stream error does not publish a partial tool call" {
  let decoder = AnthropicStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"call_1\",\"name\":\"lookup\",\"input\":{}}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\"}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"error\",\"error\":{\"message\":\"provider failed\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  let mut ready = 0
  for event in terminal.events {
    if event is @moonai.ToolCallReady(_) {
      ready = ready + 1
    }
  }
  assert_eq(ready, 0)
  assert_eq(decoder.response().finish_reason, @moonai.Error)
  assert_eq(decoder.response().tool_calls.length(), 0)
}

///|
async test "golden SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/openai/testdata/tool_calls.sse").text()
  let decoder = OpenAIStreamDecoder::new()
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
  let mut tool_delta = 0
  let mut finish = 0
  for event in events {
    match event {
      @moonai.ToolCallReady(_) => tool_ready = tool_ready + 1
      @moonai.ToolInputDelta(..) => tool_delta = tool_delta + 1
      @moonai.Finish(..) => finish = finish + 1
      _ => ()
    }
  }
  assert_eq(tool_ready, 2)
  assert_eq(tool_delta, 4)
  assert_eq(finish, 1)
}

///|
test "multiline SSE data is joined before JSON parsing" {
  let decoder = OpenAIStreamDecoder::new()
  let _ = decoder.feed_line("data: {\"choices\":[")
  let _ = decoder.feed_line(
    "data: {\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}",
  )
  let batch = decoder.feed_line("")
  assert_true(batch.consumed_event)
  assert_eq(decoder.response().text, "hello")
}

///|
test "unterminated final data line can be flushed explicitly" {
  let decoder = OpenAIStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}",
  )
  let batch = decoder.flush_buffered()
  assert_true(batch.consumed_event)
  assert_eq(decoder.response().text, "partial")
}

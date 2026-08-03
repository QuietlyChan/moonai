///|
async test "golden Open Responses SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/open_responses/testdata/responses.sse").text()
  let decoder = OpenResponsesStreamDecoder::new()
  let events : Array[@moonai.StreamEvent] = []
  for line in fixture.split("\n") {
    let batch = decoder.feed_line(line.to_owned())
    for event in batch.events {
      events.push(event)
    }
  }
  let response = decoder.response()
  assert_eq(response.text, "Checking weather.")
  assert_eq(response.reasoning, "Need a tool.")
  assert_eq(response.tool_calls, [
    @moonai.ToolCall::new(
      id="call_weather",
      name="get_weather",
      arguments="{\"city\":\"Hangzhou\"}",
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
  let mut finish = 0
  let mut tool_ready = 0
  for event in events {
    match event {
      @moonai.Finish(..) => finish = finish + 1
      @moonai.ToolCallReady(_) => tool_ready = tool_ready + 1
      _ => ()
    }
  }
  assert_eq(finish, 1)
  assert_eq(tool_ready, 1)
}

///|
test "terminal response event finalizes without DONE sentinel" {
  let decoder = OpenResponsesStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"hello\"}",
  )
  let delta = decoder.feed_line("")
  assert_eq(delta.done, false)
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  let mut finish_events = 0
  for event in terminal.events {
    if event is @moonai.Finish(..) {
      finish_events = finish_events + 1
    }
  }
  assert_eq(finish_events, 1)
  let response = decoder.response()
  assert_eq(response.text, "hello")
  assert_eq(response.finish_reason, @moonai.Stop)
  assert_eq(response.usage.total_tokens, 2)
}

///|
test "failed response closes partial tool input without making it executable" {
  let decoder = OpenResponsesStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"lookup\",\"arguments\":\"\"}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"fc_1\",\"delta\":\"{\"}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\",\"error\":{\"message\":\"request failed\"}}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  let mut errors = 0
  let mut ready = 0
  for event in terminal.events {
    match event {
      @moonai.StreamError("request failed") => errors = errors + 1
      @moonai.ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(errors, 1)
  assert_eq(ready, 0)
  assert_eq(decoder.response().finish_reason, @moonai.Error)
  assert_eq(decoder.response().tool_calls.length(), 0)
}

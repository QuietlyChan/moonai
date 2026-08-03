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
test "include_raw_chunks emits the provider event before normalized events" {
  let decoder = OpenResponsesStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_true(terminal.events[0] is @moonai.Raw(_))
  assert_true(terminal.events[1] is @moonai.Finish(..))
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

///|
test "out-of-order function call events keep metadata and stream identity" {
  let decoder = OpenResponsesStreamDecoder::new()
  let events : Array[@moonai.StreamEvent] = []
  let collect = (batch : @http_sse.DecodeBatch) => {
    for event in batch.events {
      events.push(event)
    }
  }
  // Accept argument events that arrive before output item metadata.
  collect(
    decoder.feed_line(
      "data: {\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"fc_late\",\"delta\":\"{\\\"city\\\":\\\"Paris\\\"}\"}",
    ),
  )
  collect(decoder.feed_line(""))
  collect(
    decoder.feed_line(
      "data: {\"type\":\"response.function_call_arguments.done\",\"item_id\":\"fc_late\",\"call_id\":\"call_late\",\"arguments\":\"{\\\"city\\\":\\\"Paris\\\"}\"}",
    ),
  )
  collect(decoder.feed_line(""))
  collect(
    decoder.feed_line(
      "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"fc_late\",\"type\":\"function_call\",\"call_id\":\"call_late\",\"name\":\"weather\",\"arguments\":\"\"}}",
    ),
  )
  collect(decoder.feed_line(""))
  collect(
    decoder.feed_line(
      "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"fc_late\",\"type\":\"function_call\",\"call_id\":\"call_late\",\"name\":\"weather\",\"arguments\":\"{\\\"city\\\":\\\"Paris\\\"}\"}}",
    ),
  )
  collect(decoder.feed_line(""))
  collect(
    decoder.feed_line(
      "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}",
    ),
  )
  let response = decoder.response()
  assert_eq(response.tool_calls, [
    @moonai.ToolCall::new(
      id="call_late",
      name="weather",
      arguments="{\"city\":\"Paris\"}",
    ),
  ])
  let mut starts = 0
  let mut deltas = 0
  let mut ends = 0
  for event in events {
    match event {
      @moonai.ToolInputStart(id="call_late", tool_name="weather") =>
        starts = starts + 1
      @moonai.ToolInputDelta(id="call_late", delta="{\"city\":\"Paris\"}") =>
        deltas = deltas + 1
      @moonai.ToolInputEnd("call_late") => ends = ends + 1
      _ => ()
    }
  }
  assert_eq(starts, 1)
  assert_eq(deltas, 1)
  assert_eq(ends, 1)
}

///|
test "decode non-streaming Open Responses result" {
  let response = decode_responses_response({
    "id": "resp_1",
    "status": "completed",
    "output": [
      {
        "type": "reasoning",
        "content": [{ "type": "reasoning_text", "text": "checking" }],
      },
      {
        "type": "message",
        "content": [{ "type": "output_text", "text": "Calling a tool." }],
      },
      {
        "type": "function_call",
        "call_id": "call_1",
        "name": "lookup",
        "arguments": "{\"query\":\"MoonBit\"}",
      },
    ],
    "usage": {
      "input_tokens": 4,
      "output_tokens": 3,
      "total_tokens": 7,
      "input_tokens_details": { "cached_tokens": 1 },
      "output_tokens_details": { "reasoning_tokens": 1 },
    },
  })
  assert_eq(response.text, "Calling a tool.")
  assert_eq(response.reasoning, "checking")
  assert_eq(response.tool_calls, [
    @moonai.ToolCall::new(
      id="call_1",
      name="lookup",
      arguments="{\"query\":\"MoonBit\"}",
    ),
  ])
  assert_eq(response.usage, {
    input_tokens: 4,
    output_tokens: 3,
    total_tokens: 7,
    reasoning_tokens: 1,
    cached_input_tokens: 1,
  })
  assert_eq(response.finish_reason, @moonai.ToolCalls)
}

///|
test "non-streaming Open Responses errors preserve provider detail" {
  try
    decode_responses_response({
      "status": "failed",
      "error": { "message": "upstream unavailable" },
    })
  catch {
    Failure::Failure(message) =>
      assert_true(message.contains("upstream unavailable"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected provider error")
  }
  try
    decode_responses_response({
      "status": "incomplete",
      "incomplete_details": { "reason": "content_filter" },
    })
  catch {
    Failure::Failure(message) => assert_true(message.contains("content_filter"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing output error")
  }
}

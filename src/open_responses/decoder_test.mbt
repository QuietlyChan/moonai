///|
async test "golden Open Responses SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/open_responses/testdata/responses.sse").text()
  let decoder = OpenResponsesStreamDecoder::new()
  let events : Array[@provider.StreamEvent] = []
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
    @provider.ToolCall::new(
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
    cache_write_input_tokens: 0,
  })
  assert_eq(response.finish_reason, @provider.ToolCalls)
  let mut finish = 0
  let mut tool_ready = 0
  for event in events {
    match event {
      @provider.Finish(..) => finish = finish + 1
      @provider.ToolCallReady(_) => tool_ready = tool_ready + 1
      _ => ()
    }
  }
  assert_eq(finish, 1)
  assert_eq(tool_ready, 1)
}

///|
test "Open Responses uses the injected fallback tool id" {
  let response = decode_responses_response(
    {
      "status": "completed",
      "output": [
        { "type": "function_call", "name": "lookup", "arguments": "{}" },
      ],
    },
    id_generator=() => "generated-call",
  )
  assert_eq(response.tool_calls[0].id, "generated-call")

  let decoder = OpenResponsesStreamDecoder::new(id_generator=() => {
    "generated-stream-call"
  })
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"name\":\"lookup\",\"arguments\":\"{}\"}}",
  )
  let _ = decoder.feed_line("")
  assert_eq(decoder.response().tool_calls[0].id, "generated-stream-call")
}

///|
test "reasoning summary parts retain separate stream identities" {
  let decoder = OpenResponsesStreamDecoder::new()
  let events : Array[@provider.StreamEvent] = []
  let feed = line => {
    let batch = decoder.feed_line(line)
    for event in batch.events {
      events.push(event)
    }
  }
  feed(
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"reasoning_1\",\"type\":\"reasoning\",\"summary\":[]}}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.reasoning_summary_part.added\",\"item_id\":\"reasoning_1\",\"summary_index\":0}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.reasoning_summary_text.delta\",\"item_id\":\"reasoning_1\",\"summary_index\":0,\"delta\":\"first\"}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.reasoning_summary_part.done\",\"item_id\":\"reasoning_1\",\"summary_index\":0}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.reasoning_summary_part.added\",\"item_id\":\"reasoning_1\",\"summary_index\":1}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.reasoning_summary_text.delta\",\"item_id\":\"reasoning_1\",\"summary_index\":1,\"delta\":\"second\"}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.reasoning_summary_part.done\",\"item_id\":\"reasoning_1\",\"summary_index\":1}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}}",
  )
  feed("")
  let mut first_starts = 0
  let mut second_starts = 0
  let mut first_ends = 0
  let mut second_ends = 0
  for event in events {
    match event {
      @provider.ReasoningStart("reasoning_1:0") =>
        first_starts = first_starts + 1
      @provider.ReasoningStart("reasoning_1:1") =>
        second_starts = second_starts + 1
      @provider.ReasoningDelta(id="reasoning_1:0", delta="first") => ()
      @provider.ReasoningDelta(id="reasoning_1:1", delta="second") => ()
      @provider.ReasoningEnd("reasoning_1:0") => first_ends = first_ends + 1
      @provider.ReasoningEnd("reasoning_1:1") => second_ends = second_ends + 1
      _ => ()
    }
  }
  assert_eq(first_starts, 1)
  assert_eq(second_starts, 1)
  assert_eq(first_ends, 1)
  assert_eq(second_ends, 1)
  assert_eq(decoder.response().reasoning, "firstsecond")
}

///|
test "progressive tool calls prefer the provider call id" {
  let mut generated_ids = 0
  let decoder = OpenResponsesStreamDecoder::new(progressive_tool_calls=true, id_generator=() => {
    generated_ids = generated_ids + 1
    "unused-fallback"
  })
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"provider-call\",\"name\":\"lookup\",\"arguments\":\"\"}}",
  )
  let started = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"provider-call\",\"name\":\"lookup\",\"arguments\":\"{}\"}}",
  )
  let completed = decoder.feed_line("")
  assert_eq(generated_ids, 0)
  assert_true(
    started.events[0]
    is @provider.ToolInputStart(id="provider-call", tool_name="lookup"),
  )
  assert_true(
    completed.events[0] is @provider.ToolInputDelta(id="provider-call", ..),
  )
  assert_true(completed.events[1] is @provider.ToolInputEnd("provider-call"))
  assert_true(
    completed.events[2] is @provider.ToolCallReady({ id: "provider-call", .. }),
  )
  assert_eq(decoder.response().tool_calls[0].id, "provider-call")
}

///|
test "progressive tool calls keep an emitted fallback id stable" {
  let decoder = OpenResponsesStreamDecoder::new(progressive_tool_calls=true, id_generator=() => {
    "fallback-call"
  })
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"name\":\"lookup\",\"arguments\":\"\"}}",
  )
  let started = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"late-provider-call\",\"name\":\"lookup\",\"arguments\":\"{}\"}}",
  )
  let completed = decoder.feed_line("")
  assert_true(
    started.events[0]
    is @provider.ToolInputStart(id="fallback-call", tool_name="lookup"),
  )
  assert_true(
    completed.events[0] is @provider.ToolInputDelta(id="fallback-call", ..),
  )
  assert_true(completed.events[1] is @provider.ToolInputEnd("fallback-call"))
  assert_true(
    completed.events[2] is @provider.ToolCallReady({ id: "fallback-call", .. }),
  )
  assert_eq(decoder.response().tool_calls[0].id, "fallback-call")
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
    if event is @provider.Finish(..) {
      finish_events = finish_events + 1
    }
  }
  assert_eq(finish_events, 1)
  let response = decoder.response()
  assert_eq(response.text, "hello")
  assert_eq(response.finish_reason, @provider.Stop)
  assert_eq(response.usage.total_tokens, 2)
}

///|
test "response.created emits normalized response metadata" {
  let decoder = OpenResponsesStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-created\",\"model\":\"gpt-test\",\"created_at\":1700000001}}",
  )
  let batch = decoder.feed_line("")
  match batch.events[0] {
    @provider.ResponseMetadataReady(metadata) => {
      assert_eq(metadata.id, Some("resp-created"))
      assert_eq(metadata.model_id, Some("gpt-test"))
      assert_eq(metadata.created_at, Some(1700000001))
    }
    _ => fail("expected response metadata")
  }
}

///|
test "DONE without a response terminal keeps an unknown finish reason" {
  let decoder = OpenResponsesStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"partial\"}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_true(
    terminal.events[terminal.events.length() - 1]
    is @provider.Finish(reason=@provider.Unknown(""), ..),
  )
  let response = decoder.response()
  assert_eq(response.text, "partial")
  assert_eq(response.finish_reason, @provider.Unknown(""))
}

///|
test "include_raw_chunks emits the provider event before normalized events" {
  let decoder = OpenResponsesStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_true(terminal.events[0] is @provider.Raw(_))
  assert_true(terminal.events[1] is @provider.Finish(..))
}

///|
test "failed response does not expose an incomplete tool call" {
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
  let mut ready = 0
  for event in terminal.events {
    match event {
      @provider.ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(ready, 0)
  assert_eq(decoder.response().finish_reason, @provider.Error)
  assert_eq(decoder.response().tool_calls.length(), 0)
}

///|
test "out-of-order function call events emit one complete tool call" {
  let decoder = OpenResponsesStreamDecoder::new()
  let events : Array[@provider.StreamEvent] = []
  let collect = (batch : @provider_utils.DecodeBatch) => {
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
    @provider.ToolCall::new(
      id="call_late",
      name="weather",
      arguments="{\"city\":\"Paris\"}",
    ),
  ])
  let mut starts = 0
  let mut deltas = 0
  let mut ends = 0
  let mut ready = 0
  for event in events {
    match event {
      @provider.ToolInputStart(id="call_late", tool_name="weather") =>
        starts = starts + 1
      @provider.ToolInputDelta(id="call_late", delta="{\"city\":\"Paris\"}") =>
        deltas = deltas + 1
      @provider.ToolInputEnd("call_late") => ends = ends + 1
      @provider.ToolCallReady(_) => ready = ready + 1
      _ => ()
    }
  }
  assert_eq(starts, 0)
  assert_eq(deltas, 0)
  assert_eq(ends, 0)
  assert_eq(ready, 1)
}

///|
test "terminal response does not synthesize an unfinished tool call" {
  let decoder = OpenResponsesStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.function_call_arguments.done\",\"item_id\":\"__proto__\",\"arguments\":\"not-json\"}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_eq(decoder.response().tool_calls, [])
  assert_eq(decoder.response().finish_reason, @provider.Stop)
}

///|
test "completed tool calls preserve provider string input verbatim" {
  let decoder = OpenResponsesStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"raw_tool\",\"arguments\":\"not-json\"}}",
  )
  let completed = decoder.feed_line("")
  assert_true(completed.events[0] is @provider.ToolCallReady(_))
  assert_eq(decoder.response().tool_calls, [
    @provider.ToolCall::new(id="call_1", name="raw_tool", arguments="not-json"),
  ])
}

///|
test "invalid SSE JSON becomes a recoverable stream error" {
  let decoder = OpenResponsesStreamDecoder::new()
  let _ = decoder.feed_line("data: {not-json}")
  let malformed = decoder.feed_line("")
  assert_eq(malformed.done, false)
  assert_eq(malformed.events.length(), 1)
  assert_true(malformed.events[0] is @provider.StreamError(_))

  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_true(terminal.events[0] is @provider.Finish(..))
}

///|
test "decode non-streaming Open Responses result" {
  let response = decode_responses_response({
    "id": "resp_1",
    "model": "responses-model",
    "created_at": 1700000005,
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
      "input_tokens_details": { "cached_tokens": 1, "cache_write_tokens": 2 },
      "output_tokens_details": { "reasoning_tokens": 1 },
    },
  })
  assert_eq(response.text, "Calling a tool.")
  assert_eq(response.reasoning, "checking")
  assert_eq(response.tool_calls, [
    @provider.ToolCall::new(
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
    cache_write_input_tokens: 2,
  })
  assert_eq(response.finish_reason, @provider.ToolCalls)
  assert_eq(response.response.unwrap().id, Some("resp_1"))
  assert_eq(response.response.unwrap().model_id, Some("responses-model"))
  assert_eq(response.response.unwrap().created_at, Some(1700000005))
}

///|
test "non-streaming Open Responses errors preserve provider detail" {
  try
    decode_responses_response({
      "status": "failed",
      "error": { "message": "upstream unavailable" },
    })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
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
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("content_filter"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing output error")
  }
}

///|
test "response state events retain nested response metadata" {
  let decoder = OpenResponsesStreamDecoder::new(provider_name="local.responses")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_nested\",\"model\":\"nested-model\",\"created_at\":1700000004,\"provider_metadata\":{\"local.responses\":{\"trace\":\"nested-trace\"}}}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}",
  )
  let _ = decoder.feed_line("")
  let response = decoder.response()
  match response.response {
    Some(metadata) => {
      assert_eq(metadata.id, Some("resp_nested"))
      assert_eq(metadata.model_id, Some("nested-model"))
      assert_eq(metadata.created_at, Some(1700000004))
    }
    None => fail("expected nested response metadata")
  }
  json_inspect(response.provider_metadata["local.responses"], content={
    "trace": "nested-trace",
  })
}

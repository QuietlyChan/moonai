///|
async test "golden Anthropic SSE normalizes text reasoning tools and usage" {
  let fixture = @fs.read_file("src/anthropic/testdata/messages.sse").text()
  let decoder = AnthropicStreamDecoder::new()
  let events : Array[@provider.StreamEvent] = []
  for line in fixture.split("\n") {
    let batch = decoder.feed_line(line.to_owned())
    for event in batch.events {
      events.push(event)
    }
  }
  assert_eq(decoder.text.to_string(), "It is sunny.")
  assert_eq(decoder.reasoning.to_string(), "checking tools")
  assert_eq(decoder.tool_calls, [
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
  assert_eq(decoder.usage(), {
    input_tokens: 17,
    output_tokens: 7,
    total_tokens: 24,
    reasoning_tokens: 2,
    cached_input_tokens: 3,
    cache_write_input_tokens: 2,
  })
  assert_eq(decoder.finish_reason, @provider.ToolCalls)
  assert_true(decoder.block_signatures.any(value => value == "sig_test"))
  let mut tool_ready = 0
  let mut tool_delta = 0
  let mut finish = 0
  let mut text_delta = 0
  let mut reasoning_delta = 0
  for event in events {
    match event {
      @provider.ToolCallReady(_) => tool_ready = tool_ready + 1
      @provider.ToolInputDelta(..) => tool_delta = tool_delta + 1
      @provider.Finish(..) => finish = finish + 1
      @provider.TextDelta(..) => text_delta = text_delta + 1
      @provider.ReasoningDelta(..) => reasoning_delta = reasoning_delta + 1
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
  assert_eq(decoder.text.to_string(), "partial")
}

///|
test "Anthropic message_start emits response metadata before content" {
  let decoder = AnthropicStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-test\",\"usage\":{\"input_tokens\":1}}}",
  )
  let batch = decoder.feed_line("")
  match batch.events[0] {
    @provider.ResponseMetadataReady(metadata) => {
      assert_eq(metadata.id, Some("msg-1"))
      assert_eq(metadata.model_id, Some("claude-test"))
    }
    _ => fail("expected Anthropic response metadata event")
  }
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  let content = decoder.feed_line("")
  assert_true(
    content.events.all(event => !(event is @provider.ResponseMetadataReady(_))),
  )
}

///|
test "include_raw_chunks emits Anthropic provider events once" {
  let decoder = AnthropicStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":1}}}",
  )
  let chunk = decoder.feed_line("")
  let mut raw = 0
  for event in chunk.events {
    if event is @provider.Raw(_) {
      raw = raw + 1
    }
  }
  assert_eq(raw, 1)
}

///|
test "malformed Anthropic chunks emit raw then error and the stream continues" {
  let decoder = AnthropicStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":1}}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: {\"type\":")
  let malformed = decoder.feed_line("")
  assert_true(malformed.consumed_event)
  assert_false(malformed.done)
  assert_eq(malformed.events.length(), 2)
  match malformed.events[0] {
    @provider.Raw(String(value)) => assert_eq(value, "{\"type\":")
    _ => fail("expected the malformed Anthropic raw chunk first")
  }
  match malformed.events[1] {
    @provider.StreamError(error) => {
      assert_true(error.message.contains("Anthropic stream decode error"))
      assert_eq(error.data, Some(Json::string("{\"type\":")))
    }
    _ => fail("expected an Anthropic stream error after the raw chunk")
  }
  let _ = decoder.feed_line(
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":2}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: {\"type\":\"message_stop\"}")
  let terminal = decoder.feed_line("")
  assert_false(terminal.done)
  assert_true(terminal.events.any(event => event is @provider.Finish(..)))
  assert_true(decoder.flush_buffered().done)
  assert_eq(decoder.finish_reason, @provider.Stop)
}

///|
test "schema-invalid Anthropic chunks become non-terminal stream errors" {
  let decoder = AnthropicStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_delta\",\"index\":0}",
  )
  let invalid = decoder.feed_line("")
  assert_false(invalid.done)
  assert_eq(invalid.events.length(), 1)
  match invalid.events[0] {
    @provider.StreamError(error) => {
      assert_true(error.message.contains("typed delta"))
      assert_true(
        error.data
        is Some(
          { "type": "content_block_delta", "index": Number(index, ..), .. }
        ) &&
        index == 0.0,
      )
    }
    _ => fail("expected a typed Anthropic schema error")
  }
  let _ = decoder.feed_line(
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":1}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: {\"type\":\"message_stop\"}")
  let terminal = decoder.feed_line("")
  assert_false(terminal.done)
  assert_true(decoder.flush_buffered().done)
  assert_eq(decoder.finish_reason, @provider.Stop)
}

///|
test "Anthropic stream ids match content block indexes" {
  let decoder = AnthropicStreamDecoder::new()
  let events : Array[@provider.StreamEvent] = []
  let feed = (value : String) => {
    let _ = decoder.feed_line("data: " + value)
    let batch = decoder.feed_line("")
    for event in batch.events {
      events.push(event)
    }
  }
  feed(
    "{\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  feed(
    "{\"type\":\"content_block_delta\",\"index\":2,\"delta\":{\"type\":\"text_delta\",\"text\":\"answer\"}}",
  )
  feed("{\"type\":\"content_block_stop\",\"index\":2}")
  feed(
    "{\"type\":\"content_block_start\",\"index\":4,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\"}}",
  )
  feed(
    "{\"type\":\"content_block_delta\",\"index\":4,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"plan\"}}",
  )
  feed("{\"type\":\"content_block_stop\",\"index\":4}")
  assert_true(events.any(event => event is @provider.TextStart("2")))
  assert_true(events.any(event => event is @provider.TextDelta(id="2", ..)))
  assert_true(events.any(event => event is @provider.TextEnd("2")))
  assert_true(events.any(event => event is @provider.ReasoningStart("4")))
  assert_true(
    events.any(event => event is @provider.ReasoningDelta(id="4", ..)),
  )
  assert_true(events.any(event => event is @provider.ReasoningEnd("4")))
}

///|
test "Anthropic streams pre-populated tool calls across message boundaries" {
  let decoder = AnthropicStreamDecoder::new(provider_name="anthropic.messages")
  let events : Array[@provider.StreamEvent] = []
  let feed = (value : String) => {
    let _ = decoder.feed_line("data: " + value)
    let batch = decoder.feed_line("")
    for event in batch.events {
      events.push(event)
    }
    batch
  }
  let _ = feed(
    "{\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-test\",\"content\":[{\"type\":\"tool_use\",\"id\":\"call-1\",\"name\":\"lookup\",\"input\":{\"city\":\"Hangzhou\"},\"caller\":{\"type\":\"code_execution_20250825\",\"tool_id\":\"server-1\"}}],\"stop_reason\":\"tool_use\",\"usage\":{\"input_tokens\":10,\"output_tokens\":0}}}",
  )
  let first_stop = feed("{\"type\":\"message_stop\"}")
  assert_false(first_stop.done)
  let _ = feed(
    "{\"type\":\"message_start\",\"message\":{\"id\":\"msg-2\",\"model\":\"claude-test\",\"content\":[{\"type\":\"tool_use\",\"id\":\"call-2\",\"name\":\"lookup\",\"input\":{\"city\":\"Shanghai\"}}],\"stop_reason\":\"tool_use\",\"usage\":{\"input_tokens\":0,\"output_tokens\":0}}}",
  )
  let second_stop = feed("{\"type\":\"message_stop\"}")
  assert_false(second_stop.done)
  let done = feed("[DONE]")
  assert_true(done.done)
  let mut metadata_count = 0
  let mut finish_count = 0
  let mut first_finish_input = -1
  let mut second_finish_input = -1
  for event in events {
    match event {
      @provider.ResponseMetadataReady(_) => metadata_count = metadata_count + 1
      @provider.Finish(usage~, ..) => {
        if finish_count == 0 {
          first_finish_input = usage.input_tokens
        } else {
          second_finish_input = usage.input_tokens
        }
        finish_count = finish_count + 1
      }
      _ => ()
    }
  }
  assert_eq(metadata_count, 2)
  assert_eq(finish_count, 2)
  assert_eq(first_finish_input, 10)
  assert_eq(second_finish_input, 0)
  assert_true(
    events.any(event => event is @provider.ToolInputStart(id="call-1", ..)),
  )
  assert_true(
    events.any(event => {
      event
      is @provider.ToolInputDelta(id="call-1", delta="{\"city\":\"Hangzhou\"}")
    }),
  )
  assert_true(events.any(event => event is @provider.ToolInputEnd("call-1")))
  assert_true(
    events.any(event => {
      event
      is @provider.ToolCallReady(
        {
          id: "call-2",
          name: "lookup",
          arguments: "{\"city\":\"Shanghai\"}",
          ..,
        }
      )
    }),
  )
  let mut found_first_call = false
  for event in events {
    match event {
      @provider.ToolCallReady(call) if call.id == "call-1" => {
        found_first_call = true
        json_inspect(call.provider_metadata["anthropic.messages"], content={
          "caller": { "type": "code_execution_20250825", "toolId": "server-1" },
        })
      }
      _ => ()
    }
  }
  assert_true(found_first_call)
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
    "data: {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"provider failed\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  let mut ready = 0
  let mut errors = 0
  let mut finishes = 0
  for event in terminal.events {
    match event {
      @provider.ToolCallReady(_) => ready = ready + 1
      @provider.StreamError(error) => {
        assert_eq(error.message, "provider failed")
        assert_true(error.data is Some({ "message": "provider failed", .. }))
        errors = errors + 1
      }
      @provider.Finish(..) => finishes = finishes + 1
      _ => ()
    }
  }
  assert_eq(ready, 0)
  assert_eq(errors, 1)
  assert_eq(finishes, 0)
  assert_eq(decoder.finish_reason, @provider.Error)
  assert_eq(decoder.tool_calls.length(), 0)
}

///|
test "Anthropic V4 stream forwards raw error without a synthetic finish" {
  let decoder = AnthropicV4StreamDecoder::new(
    emit_raw_chunks=true,
    provider_name="anthropic.messages",
    canonical_metadata=true,
    include_custom_provider_metadata=false,
    mark_code_execution_dynamic=false,
    uses_json_response_tool=false,
    tool_name_mapping=@provider_utils.ToolNameMapping::identity(),
    id_generator=() => "generated-id",
    citation_documents=[],
  )
  let _ = decoder.feed_line(
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-test\",\"usage\":{\"input_tokens\":1}}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_true(terminal.done)
  assert_eq(terminal.events.length(), 2)
  assert_true(terminal.events[0] is @provider.V4Raw(_))
  match terminal.events[1] {
    @provider.V4Error(error) => {
      assert_eq(error.message, "Overloaded")
      assert_true(
        error.data
        is Some({ "type": "overloaded_error", "message": "Overloaded", .. }),
      )
    }
    _ => fail("expected the Anthropic V4 error after its raw chunk")
  }
  assert_false(terminal.events.any(event => event is @provider.V4Finish(..)))
}

///|
test "Anthropic V4 stream preserves empty content deltas" {
  let decoder = AnthropicV4StreamDecoder::new(
    emit_raw_chunks=false,
    provider_name="anthropic.messages",
    canonical_metadata=true,
    include_custom_provider_metadata=false,
    mark_code_execution_dynamic=false,
    uses_json_response_tool=false,
    tool_name_mapping=@provider_utils.ToolNameMapping::identity(),
    id_generator=() => "generated-id",
    citation_documents=[],
  )
  let feed = (value : String) => {
    let _ = decoder.feed_line("data: " + value)
    decoder.feed_line("")
  }
  let _ = feed(
    "{\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-test\",\"usage\":{\"input_tokens\":1}}}",
  )
  let _ = feed(
    "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  let text = feed(
    "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"\"}}",
  )
  assert_true(
    text.events.any(event => event is @provider.V4TextDelta(delta="", ..)),
  )
  let _ = feed(
    "{\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\"}}",
  )
  let reasoning = feed(
    "{\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"\"}}",
  )
  assert_true(
    reasoning.events.any(event => {
      event is @provider.V4ReasoningDelta(delta="", ..)
    }),
  )
  let _ = feed(
    "{\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"compaction\",\"content\":null}}",
  )
  let compaction = feed(
    "{\"type\":\"content_block_delta\",\"index\":2,\"delta\":{\"type\":\"compaction_delta\",\"content\":\"\"}}",
  )
  assert_true(
    compaction.events.any(event => event is @provider.V4TextDelta(delta="", ..)),
  )
}

///|
test "Anthropic V4 stream finish includes nullable metadata fields" {
  let decoder = AnthropicV4StreamDecoder::new(
    emit_raw_chunks=false,
    provider_name="anthropic.messages",
    canonical_metadata=true,
    include_custom_provider_metadata=false,
    mark_code_execution_dynamic=false,
    uses_json_response_tool=false,
    tool_name_mapping=@provider_utils.ToolNameMapping::identity(),
    id_generator=() => "generated-id",
    citation_documents=[],
  )
  let feed = (value : String) => {
    let _ = decoder.feed_line("data: " + value)
    decoder.feed_line("")
  }
  let _ = feed(
    "{\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-test\",\"usage\":{\"input_tokens\":1}}}",
  )
  let _ = feed(
    "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":2}}",
  )
  let stopped = feed("{\"type\":\"message_stop\"}")
  let mut found = false
  for event in stopped.events {
    match event {
      @provider.V4Finish(provider_metadata~, ..) => {
        found = true
        match provider_metadata["anthropic"] {
          {
            "usage": { "output_tokens": Number(_, ..), .. },
            "stopSequence": Null,
            "iterations": Null,
            "container": Null,
            "contextManagement": Null,
            ..
          } => ()
          _ => fail("expected complete nullable Anthropic stream metadata")
        }
      }
      _ => ()
    }
  }
  assert_true(found)
}

///|
test "negative Anthropic content indexes retain the offending chunk" {
  let decoder = AnthropicStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":-1,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  try decoder.feed_line("") catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("non-negative"))
      assert_true(data is { "index": Number(value, ..), .. } && value == -1.0)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed Anthropic content-index response error")
  }
}

///|
test "decode non-streaming Anthropic Messages response" {
  let response = decode_messages_response({
    "id": "msg_1",
    "model": "claude-sonnet-4-6",
    "content": [
      { "type": "thinking", "thinking": "reason" },
      { "type": "text", "text": "answer" },
      {
        "type": "tool_use",
        "id": "call_1",
        "name": "lookup",
        "input": { "query": "MoonBit" },
      },
    ],
    "stop_reason": "tool_use",
    "usage": {
      "input_tokens": 5,
      "output_tokens": 3,
      "cache_read_input_tokens": 2,
      "thinking_tokens": 1,
    },
    "provider_metadata": { "anthropic.messages": { "trace_id": "a-2" } },
  })
  assert_eq(response.text, "answer")
  assert_eq(response.reasoning, "reason")
  assert_eq(response.tool_calls, [
    @provider.ToolCall::new(
      id="call_1",
      name="lookup",
      arguments="{\"query\":\"MoonBit\"}",
    ),
  ])
  assert_eq(response.finish_reason, @provider.ToolCalls)
  assert_eq(response.usage.input_tokens, 7)
  assert_eq(response.usage.reasoning_tokens, 1)
  json_inspect(response.provider_metadata["anthropic.messages"], content={
    "trace_id": "a-2",
    "usage": {
      "input_tokens": 5,
      "output_tokens": 3,
      "cache_read_input_tokens": 2,
      "thinking_tokens": 1,
    },
    "stopSequence": null,
    "iterations": null,
    "container": null,
    "contextManagement": null,
  })
}

///|
test "Anthropic JSON response tool decodes directly to V4 text" {
  let decoded = decode_messages_response_with_metadata(
    {
      "id": "msg-json",
      "model": "claude-sonnet-4-6",
      "content": [
        { "type": "text", "text": "I will format the response." },
        {
          "type": "tool_use",
          "id": "json-call",
          "name": "json",
          "input": { "city": "Hangzhou" },
        },
      ],
      "stop_reason": "tool_use",
      "usage": { "input_tokens": 3, "output_tokens": 4 },
    },
    provider_name="anthropic.messages",
    canonical_metadata=true,
    include_custom_provider_metadata=false,
    mark_code_execution_dynamic=false,
    uses_json_response_tool=true,
    tool_name_mapping=@provider_utils.ToolNameMapping::identity(),
    id_generator=() => "source-id",
    citation_documents=[],
  )
  assert_eq(decoded.content.length(), 1)
  match decoded.content[0] {
    @provider.V4TextOutput(value) =>
      assert_eq(value.text, "{\"city\":\"Hangzhou\"}")
    _ => fail("expected the Anthropic JSON tool input as V4 text")
  }
  assert_eq(decoded.finish_reason.unified, @provider.V4FinishStop)
  assert_eq(decoded.finish_reason.raw, Some("tool_use"))
  assert_eq(decoded.usage.input_tokens.total, Some(3))
  assert_eq(decoded.usage.output_tokens.total, Some(4))
  match decoded.provider_metadata["anthropic"] {
    {
      "usage": { "input_tokens": Number(_, ..), .. },
      "stopSequence": Null,
      "iterations": Null,
      "container": Null,
      "contextManagement": Null,
      ..
    } => ()
    _ => fail("expected complete nullable Anthropic metadata")
  }
}

///|
test "Anthropic JSON response tool streams as text without tool events" {
  let decoder = AnthropicStreamDecoder::new(uses_json_response_tool=true)
  let payloads = [
    "{\"type\":\"message_start\",\"message\":{\"id\":\"msg-json-stream\",\"model\":\"claude-sonnet-4-6\",\"usage\":{\"input_tokens\":2}}}",
    "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
    "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"preface\"}}",
    "{\"type\":\"content_block_stop\",\"index\":0}", "{\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"json-call\",\"name\":\"json\",\"input\":{}}}",
    "{\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"city\\\":\\\"Hangzhou\\\"}\"}}",
    "{\"type\":\"content_block_stop\",\"index\":1}", "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":4}}",
    "{\"type\":\"message_stop\"}",
  ]
  let events : Array[@provider.StreamEvent] = []
  for payload in payloads {
    ignore(decoder.feed_line("data: " + payload))
    let batch = decoder.feed_line("")
    for event in batch.events {
      events.push(event)
    }
  }
  let mut starts = 0
  let mut ends = 0
  let deltas : Array[String] = []
  let mut tool_events = 0
  let mut finish_reason = @provider.Unknown("")
  for event in events {
    match event {
      @provider.TextStart(_) => starts = starts + 1
      @provider.TextDelta(delta~, ..) => deltas.push(delta)
      @provider.TextEnd(_) => ends = ends + 1
      @provider.ToolInputStart(..)
      | @provider.ToolInputDelta(..)
      | @provider.ToolInputEnd(_)
      | @provider.ToolCallReady(_) => tool_events = tool_events + 1
      @provider.Finish(reason~, ..) => finish_reason = reason
      _ => ()
    }
  }
  assert_eq(starts, 1)
  assert_eq(deltas, ["{\"city\":\"Hangzhou\"}"])
  assert_eq(ends, 1)
  assert_eq(tool_events, 0)
  assert_eq(finish_reason, @provider.Stop)
  assert_eq(decoder.text.to_string(), "{\"city\":\"Hangzhou\"}")
  assert_eq(decoder.tool_calls.length(), 0)
  assert_eq(decoder.finish_reason, @provider.Stop)
  assert_eq(decoder.v4_finish_reason().unified, @provider.V4FinishStop)
  assert_eq(decoder.v4_finish_reason().raw, Some("tool_use"))
}

///|
test "Anthropic preserves tool caller metadata" {
  let response = decode_messages_response({
    "content": [
      {
        "type": "tool_use",
        "id": "call-program",
        "name": "query_database",
        "input": { "sql": "select 1" },
        "caller": {
          "type": "code_execution_20260120",
          "tool_id": "server-code",
        },
      },
      {
        "type": "tool_use",
        "id": "call-direct",
        "name": "get_weather",
        "input": { "city": "Tokyo" },
        "caller": { "type": "direct" },
      },
    ],
    "stop_reason": "tool_use",
  })
  json_inspect(response.tool_calls[0].provider_metadata["anthropic"], content={
    "caller": { "type": "code_execution_20260120", "toolId": "server-code" },
  })
  json_inspect(response.tool_calls[1].provider_metadata["anthropic"], content={
    "caller": { "type": "direct" },
  })
}

///|
test "Anthropic stream preserves tool caller metadata" {
  let decoder = AnthropicStreamDecoder::new(provider_name="anthropic.messages")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"call-program\",\"name\":\"query_database\",\"input\":{},\"caller\":{\"type\":\"code_execution_20250825\",\"tool_id\":\"server-code\"}}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"sql\\\":\\\"select 1\\\"}\"}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_stop\",\"index\":0}",
  )
  let stopped = decoder.feed_line("")
  let mut found = false
  for event in stopped.events {
    match event {
      @provider.ToolCallReady(call) => {
        found = true
        json_inspect(call.provider_metadata["anthropic"], content={
          "caller": {
            "type": "code_execution_20250825",
            "toolId": "server-code",
          },
        })
      }
      _ => ()
    }
  }
  assert_true(found)
  json_inspect(decoder.tool_calls[0].provider_metadata["anthropic.messages"], content={
    "caller": { "type": "code_execution_20250825", "toolId": "server-code" },
  })
}

///|
test "Anthropic uses injected ids for citations and missing tool ids" {
  let mut next = 0
  let response = decode_messages_response(
    {
      "content": [
        {
          "type": "text",
          "text": "cited",
          "citations": [
            {
              "type": "web_search_result_location",
              "url": "https://example.com",
              "title": "Example",
            },
          ],
        },
        { "type": "tool_use", "name": "lookup", "input": Json::empty_object() },
      ],
      "stop_reason": "tool_use",
      "usage": { "input_tokens": 1, "output_tokens": 1 },
    },
    id_generator=() => {
      let value = if next == 0 { "source-id" } else { "tool-id" }
      next = next + 1
      value
    },
  )
  match response.content[1] {
    @provider.GeneratedSourceOutput(@provider.GeneratedUrlSource(id~, ..)) =>
      assert_eq(id, "source-id")
    _ => fail("expected citation source")
  }
  assert_eq(response.tool_calls[0].id, "tool-id")

  let stream = AnthropicStreamDecoder::new(id_generator=() => "stream-tool-id")
  let _ = stream.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"name\":\"lookup\",\"input\":{}}}",
  )
  let started = stream.feed_line("")
  assert_true(
    started.events.any(event => {
      event is @provider.ToolInputStart(id="stream-tool-id", ..)
    }),
  )
}

///|
test "Anthropic preserves thinking signatures in response metadata" {
  let response = decode_messages_response(
    {
      "id": "msg_signature",
      "content": [
        { "type": "thinking", "thinking": "reason", "signature": "sig_123" },
        { "type": "text", "text": "answer" },
      ],
      "stop_reason": "end_turn",
      "usage": { "input_tokens": 1, "output_tokens": 1 },
    },
    provider_name="anthropic.messages",
  )
  let mut found = false
  for part in response.content {
    match part {
      @provider.GeneratedReasoningOutput(value) => {
        found = true
        json_inspect(value.provider_metadata["anthropic.messages"], content={
          "signature": "sig_123",
        })
      }
      _ => ()
    }
  }
  assert_true(found)
}

///|
test "Anthropic maps text citations to normalized sources" {
  let response = decode_messages_response(
    {
      "content": [
        {
          "type": "text",
          "text": "According to the sources.",
          "citations": [
            {
              "type": "web_search_result_location",
              "url": "https://example.com/article",
              "title": "Example article",
              "cited_text": "A cited sentence",
              "encrypted_index": "idx-1",
            },
            {
              "type": "page_location",
              "document_index": 0,
              "document_title": "Guide",
              "start_page_number": 2,
              "end_page_number": 3,
              "cited_text": "A page excerpt",
            },
            {
              "type": "char_location",
              "document_index": 1,
              "document_title": "Reference",
              "start_char_index": 10,
              "end_char_index": 24,
              "cited_text": "A character excerpt",
              "media_type": "text/markdown",
              "filename": "ignored-reference.md",
            },
          ],
        },
      ],
    },
    citation_documents=[
      {
        title: "Prompt guide",
        filename: Some("guide.pdf"),
        media_type: "application/pdf",
      },
      {
        title: "Prompt reference",
        filename: Some("reference.txt"),
        media_type: "text/plain",
      },
    ],
  )
  assert_eq(response.content.length(), 4)
  match response.content[0] {
    @provider.GeneratedTextOutput(value) =>
      match value.provider_metadata["anthropic.messages"] {
        { "citations": Array(citations), .. } => {
          assert_eq(citations.length(), 1)
          assert_true(
            citations[0]
            is {
              "type": "web_search_result_location",
              "url": "https://example.com/article",
              ..
            },
          )
        }
        _ => fail("expected Anthropic citations on text output")
      }
    _ => fail("expected cited text output")
  }
  match response.content[1] {
    @provider.GeneratedSourceOutput(
      @provider.GeneratedUrlSource(url~, title~, provider_metadata~, ..)
    ) => {
      assert_eq(url, "https://example.com/article")
      assert_eq(title, Some("Example article"))
      json_inspect(provider_metadata["anthropic.messages"], content={
        "citedText": "A cited sentence",
        "encryptedIndex": "idx-1",
      })
    }
    _ => fail("expected a URL citation source")
  }
  match response.content[2] {
    @provider.GeneratedSourceOutput(
      @provider.GeneratedDocumentSource(
        media_type~,
        title~,
        filename~,
        provider_metadata~,
        ..
      )
    ) => {
      assert_eq(media_type, "application/pdf")
      assert_eq(title, "Guide")
      assert_eq(filename, Some("guide.pdf"))
      json_inspect(provider_metadata["anthropic.messages"], content={
        "citedText": "A page excerpt",
        "startPageNumber": 2,
        "endPageNumber": 3,
      })
    }
    _ => fail("expected a document citation source")
  }
  match response.content[3] {
    @provider.GeneratedSourceOutput(
      @provider.GeneratedDocumentSource(
        media_type~,
        title~,
        filename~,
        provider_metadata~,
        ..
      )
    ) => {
      assert_eq(media_type, "text/plain")
      assert_eq(title, "Reference")
      assert_eq(filename, Some("reference.txt"))
      json_inspect(provider_metadata["anthropic.messages"], content={
        "citedText": "A character excerpt",
        "startCharIndex": 10,
        "endCharIndex": 24,
      })
    }
    _ => fail("expected a character-range document citation source")
  }
}

///|
test "Anthropic extracts citation-enabled prompt documents in user order" {
  let documents = extract_anthropic_citation_documents(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4AssistantMessage(
        content=[
          @provider.V4PromptFile(
            data=@provider.V4FileData("ignored"),
            media_type="application/pdf",
            filename=Some("assistant.pdf"),
            provider_options={
              "anthropic": { "citations": { "enabled": true } },
            },
          ),
        ],
        provider_options=Map([]),
      ),
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptFile(
            data=@provider.V4FileData("pdf"),
            media_type="application/pdf",
            filename=Some("guide.pdf"),
            provider_options={
              "anthropic": { "citations": { "enabled": true } },
            },
          ),
          @provider.V4PromptFile(
            data=@provider.V4FileText("plain"),
            media_type="text/plain",
            filename=None,
            provider_options={
              "anthropic": { "citations": { "enabled": true } },
            },
          ),
          @provider.V4PromptFile(
            data=@provider.V4FileData("disabled"),
            media_type="application/pdf",
            filename=Some("disabled.pdf"),
            provider_options=Map([]),
          ),
        ],
        provider_options=Map([]),
      ),
    ]),
    "anthropic.messages",
  )
  assert_eq(documents.length(), 2)
  assert_eq(documents[0].title, "guide.pdf")
  assert_eq(documents[0].filename, Some("guide.pdf"))
  assert_eq(documents[0].media_type, "application/pdf")
  assert_eq(documents[1].title, "Untitled Document")
  assert_eq(documents[1].filename, None)
  assert_eq(documents[1].media_type, "text/plain")
}

///|
test "Anthropic web fetch results register documents for later citations" {
  let response = decode_messages_response({
    "content": [
      {
        "type": "web_fetch_tool_result",
        "tool_use_id": "fetch-1",
        "content": {
          "type": "web_fetch_result",
          "url": "https://example.com/guide",
          "content": {
            "type": "document",
            "title": Json::null(),
            "source": {
              "type": "text",
              "media_type": "text/plain",
              "data": "Guide",
            },
          },
        },
      },
      {
        "type": "text",
        "text": "Fetched citation",
        "citations": [
          {
            "type": "char_location",
            "document_index": 0,
            "document_title": Json::null(),
            "start_char_index": 0,
            "end_char_index": 5,
            "cited_text": "Guide",
          },
        ],
      },
    ],
  })
  assert_eq(response.content.length(), 3)
  match response.content[2] {
    @provider.GeneratedSourceOutput(
      @provider.GeneratedDocumentSource(media_type~, title~, filename~, ..)
    ) => {
      assert_eq(media_type, "text/plain")
      assert_eq(title, "https://example.com/guide")
      assert_eq(filename, None)
    }
    _ => fail("expected a document source backed by web fetch")
  }

  let decoder = AnthropicStreamDecoder::new()
  let feed = (value : String) => {
    let _ = decoder.feed_line("data: " + value)
    decoder.feed_line("")
  }
  let _ = feed(
    "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"web_fetch_tool_result\",\"tool_use_id\":\"fetch-1\",\"content\":{\"type\":\"web_fetch_result\",\"url\":\"https://example.com/guide\",\"content\":{\"type\":\"document\",\"title\":\"Fetched guide\",\"source\":{\"type\":\"text\",\"media_type\":\"text/plain\",\"data\":\"Guide\"}}}}}",
  )
  let _ = feed(
    "{\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  let cited = feed(
    "{\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"citations_delta\",\"citation\":{\"type\":\"char_location\",\"document_index\":0,\"document_title\":null,\"start_char_index\":0,\"end_char_index\":5,\"cited_text\":\"Guide\"}}}",
  )
  assert_true(
    cited.events.any(event => {
      event
      is @provider.SourceReady(
        @provider.GeneratedDocumentSource(
          media_type="text/plain",
          title="Fetched guide",
          ..
        )
      )
    }),
  )
}

///|
test "Anthropic citation deltas emit SourceReady and persist in response" {
  let decoder = AnthropicStreamDecoder::new(provider_name="anthropic.messages")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"citations_delta\",\"citation\":{\"type\":\"web_search_result_location\",\"url\":\"https://example.com\",\"title\":\"Example\"}}}",
  )
  let batch = decoder.feed_line("")
  let mut sources = 0
  for event in batch.events {
    if event is @provider.SourceReady(_) {
      sources = sources + 1
    }
  }
  assert_eq(sources, 1)
  assert_eq(decoder.sources.length(), 1)
}

///|
test "Anthropic maps extended content blocks and response metadata" {
  let response = decode_messages_response({
    "id": "msg_extended",
    "model": "claude-test",
    "content": [
      { "type": "redacted_thinking", "data": "encrypted-thinking" },
      { "type": "compaction", "content": "conversation summary" },
      {
        "type": "server_tool_use",
        "id": "server_1",
        "name": "code_execution",
        "input": { "code": "print(1)" },
      },
      {
        "type": "mcp_tool_use",
        "id": "mcp_1",
        "name": "search_docs",
        "server_name": "docs",
        "input": { "query": "MoonBit" },
      },
      {
        "type": "mcp_tool_result",
        "tool_use_id": "mcp_1",
        "is_error": false,
        "content": [{ "type": "text", "text": "found" }],
      },
      { "type": "fallback", "model": "claude-fallback" },
    ],
    "stop_reason": "refusal",
    "stop_sequence": "END",
    "stop_details": {
      "type": "refusal",
      "category": "safety",
      "explanation": "blocked",
      "recommended_model": "claude-safe",
    },
    "container": {
      "id": "container_1",
      "expires_at": "2026-08-04T00:00:00Z",
      "skills": [
        { "type": "custom", "skill_id": "skill_1", "version": "latest" },
      ],
    },
    "context_management": {
      "applied_edits": [
        {
          "type": "clear_tool_uses_20250919",
          "cleared_tool_uses": 2,
          "cleared_input_tokens": 8,
        },
        { "type": "compact_20260112" },
      ],
    },
    "usage": {
      "input_tokens": 1,
      "output_tokens": 1,
      "cache_creation_input_tokens": 1,
      "cache_read_input_tokens": 2,
      "output_tokens_details": { "thinking_tokens": 1 },
      "iterations": [
        { "type": "compaction", "input_tokens": 4, "output_tokens": 1 },
        { "type": "message", "input_tokens": 5, "output_tokens": 2 },
        {
          "type": "advisor_message",
          "model": "advisor",
          "input_tokens": 99,
          "output_tokens": 99,
        },
      ],
    },
  })
  assert_eq(response.finish_reason, @provider.ContentFilter)
  assert_eq(response.usage.input_tokens, 12)
  assert_eq(response.usage.output_tokens, 3)
  assert_eq(response.usage.reasoning_tokens, 1)
  assert_eq(response.tool_calls.length(), 2)
  assert_eq(response.tool_calls[0].provider_executed, true)
  assert_eq(
    response.tool_calls[0].arguments,
    "{\"type\":\"programmatic-tool-call\",\"code\":\"print(1)\"}",
  )
  assert_eq(response.tool_calls[1].dynamic, true)
  assert_eq(response.content.length(), 5)
  match response.content[0] {
    @provider.GeneratedReasoningOutput(value) =>
      json_inspect(value.provider_metadata["anthropic.messages"], content={
        "redactedData": "encrypted-thinking",
      })
    _ => fail("expected redacted reasoning")
  }
  match response.content[4] {
    @provider.GeneratedToolResultOutput(value) => {
      assert_eq(value.tool_name, "search_docs")
      assert_eq(value.dynamic, true)
    }
    _ => fail("expected mcp tool result")
  }
  match response.provider_metadata["anthropic.messages"] {
    {
      "stopSequence": String(sequence),
      "stopDetails": { "recommendedModel": String(model), .. },
      "iterations": Array(iterations),
      "container": {
        "expiresAt": String(expires_at),
        "skills": Array(skills),
        ..
      },
      "contextManagement": { "appliedEdits": Array(edits), .. },
      ..
    } => {
      assert_eq(sequence, "END")
      assert_eq(model, "claude-safe")
      assert_eq(iterations.length(), 3)
      assert_eq(expires_at, "2026-08-04T00:00:00Z")
      assert_eq(skills.length(), 1)
      assert_eq(edits.length(), 2)
    }
    _ => fail("expected Anthropic response metadata")
  }
}

///|
test "Anthropic stream handles redacted thinking server tools and MCP results" {
  let decoder = AnthropicStreamDecoder::new(provider_name="anthropic.messages")
  let events : Array[@provider.StreamEvent] = []
  let feed = (line : String) => {
    let batch = decoder.feed_line(line)
    for event in batch.events {
      events.push(event)
    }
  }
  feed(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"redacted_thinking\",\"data\":\"opaque\"}}",
  )
  feed("")
  feed("data: {\"type\":\"content_block_stop\",\"index\":0}")
  feed("")
  feed(
    "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"server_tool_use\",\"id\":\"server_1\",\"name\":\"web_search\",\"input\":{\"query\":\"MoonBit\"}}}",
  )
  feed("")
  feed("data: {\"type\":\"content_block_stop\",\"index\":1}")
  feed("")
  feed(
    "data: {\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"mcp_tool_use\",\"id\":\"mcp_1\",\"name\":\"search\",\"server_name\":\"docs\",\"input\":{\"q\":\"x\"}}}",
  )
  feed("")
  feed(
    "data: {\"type\":\"content_block_start\",\"index\":3,\"content_block\":{\"type\":\"mcp_tool_result\",\"tool_use_id\":\"mcp_1\",\"is_error\":false,\"content\":{\"ok\":true}}}",
  )
  feed("")
  feed("data: {\"type\":\"message_stop\"}")
  feed("")
  assert_eq(decoder.finish_reason, @provider.ToolCalls)
  assert_eq(decoder.tool_calls.length(), 2)
  assert_eq(decoder.tool_calls[0].provider_executed, true)
  assert_eq(decoder.tool_calls[1].dynamic, true)
  assert_true(decoder.block_redacted_data.any(value => value == "opaque"))
  assert_eq(decoder.tool_results.length(), 1)
  let mut tool_ready = 0
  let mut result_ready = 0
  for event in events {
    match event {
      @provider.ToolCallReady(_) => tool_ready = tool_ready + 1
      @provider.ToolResultReady(_) => result_ready = result_ready + 1
      _ => ()
    }
  }
  assert_eq(tool_ready, 2)
  assert_eq(result_ready, 1)
}

///|
test "Anthropic emits complete MCP parts immediately and normalizes code deltas" {
  let decoder = AnthropicStreamDecoder::new(provider_name="anthropic.messages")
  let flush = (value : String) => {
    let _ = decoder.feed_line("data: " + value)
    decoder.feed_line("")
  }
  let server_start = flush(
    "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"server_tool_use\",\"id\":\"code-1\",\"name\":\"code_execution\",\"input\":{}}}",
  )
  assert_true(
    server_start.events.any(event => {
      event is @provider.ToolInputStart(id="code-1", ..)
    }),
  )
  let code_delta = flush(
    "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"code\\\":\\\"print(1)\\\"}\"}}",
  )
  assert_true(
    code_delta.events.any(event => {
      event
      is @provider.ToolInputDelta(
        id="code-1",
        delta="{\"type\": \"programmatic-tool-call\",\"code\":\"print(1)\"}"
      )
    }),
  )
  let code_stop = flush("{\"type\":\"content_block_stop\",\"index\":0}")
  assert_true(
    code_stop.events.any(event => {
      event
      is @provider.ToolCallReady(
        {
          id: "code-1",
          arguments: "{\"type\": \"programmatic-tool-call\",\"code\":\"print(1)\"}",
          ..,
        }
      )
    }),
  )

  let mcp_call = flush(
    "{\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"mcp_tool_use\",\"id\":\"mcp-1\",\"name\":\"search\",\"server_name\":\"docs\",\"input\":{\"q\":\"MoonBit\"}}}",
  )
  assert_true(
    mcp_call.events.any(event => {
      event is @provider.ToolCallReady({ id: "mcp-1", dynamic: true, .. })
    }),
  )
  assert_false(
    mcp_call.events.any(event => event is @provider.ToolInputStart(..)),
  )
  assert_false(mcp_call.events.any(event => event is @provider.ToolInputEnd(_)))

  let mcp_result = flush(
    "{\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"mcp_tool_result\",\"tool_use_id\":\"mcp-1\",\"is_error\":false,\"content\":{\"ok\":true}}}",
  )
  assert_true(
    mcp_result.events.any(event => {
      event is @provider.ToolResultReady({ tool_call_id: "mcp-1", .. })
    }),
  )
  let result_stop = flush("{\"type\":\"content_block_stop\",\"index\":2}")
  assert_false(
    result_stop.events.any(event => event is @provider.ToolResultReady(_)),
  )
}

///|
test "Anthropic retains unknown response blocks as custom content" {
  let response = decode_messages_response({
    "content": [
      { "type": "future_block", "payload": { "value": 1 } },
      { "type": "fallback", "model": "secondary" },
    ],
  })
  assert_eq(response.content.length(), 1)
  match response.content[0] {
    @provider.GeneratedCustomOutput(value) => {
      assert_eq(value.kind, "future_block")
      match value.provider_metadata["anthropic"] {
        {
          "type": "future_block",
          "raw": { "payload": { "value": 1, .. }, .. },
          ..
        } => ()
        _ => fail("expected raw custom block metadata")
      }
    }
    _ => fail("expected custom content")
  }
}

///|
test "Anthropic non-stream response maps hosted tool names to custom names" {
  let mapping = @provider_utils.create_tool_name_mapping(
    [
      @provider.ToolDefinition::provider(
        id="anthropic.web_search_20260209",
        name="research",
      ),
    ],
    Map([("anthropic.web_search_20260209", "web_search")]),
  )
  let response = decode_messages_response(
    {
      "content": [
        {
          "type": "server_tool_use",
          "id": "server_1",
          "name": "web_search",
          "input": { "query": "MoonBit" },
        },
        {
          "type": "web_search_tool_result",
          "tool_use_id": "server_1",
          "content": { "type": "web_search_result", "results": [] },
        },
      ],
    },
    tool_name_mapping=mapping,
  )
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) => assert_eq(call.name, "research")
    _ => fail("expected mapped Anthropic tool call")
  }
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      assert_eq(result.tool_name, "research")
    _ => fail("expected mapped Anthropic tool result")
  }
}

///|
test "Anthropic stream maps hosted tool events to custom names" {
  let decoder = AnthropicStreamDecoder::new(
    tool_name_mapping=@provider_utils.create_tool_name_mapping(
      [
        @provider.ToolDefinition::provider(
          id="anthropic.web_search_20260209",
          name="research",
        ),
      ],
      Map([("anthropic.web_search_20260209", "web_search")]),
    ),
  )
  let events : Array[@provider.StreamEvent] = []
  let feed = (line : String) => {
    let batch = decoder.feed_line(line)
    for event in batch.events {
      events.push(event)
    }
  }
  feed(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"server_tool_use\",\"id\":\"server_1\",\"name\":\"web_search\",\"input\":{\"query\":\"MoonBit\"}}}",
  )
  feed("")
  feed("data: {\"type\":\"content_block_stop\",\"index\":0}")
  feed("")
  feed(
    "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"web_search_tool_result\",\"tool_use_id\":\"server_1\",\"content\":{\"type\":\"web_search_result\",\"results\":[]}}}",
  )
  feed("")
  feed("data: {\"type\":\"message_stop\"}")
  feed("")
  assert_true(
    events.any(event => {
      event is @provider.ToolInputStart(tool_name="research", ..)
    }),
  )
  assert_true(
    events.any(event => {
      event is @provider.ToolCallReady({ name: "research", .. })
    }),
  )
  assert_true(
    events.any(event => {
      event is @provider.ToolResultReady({ tool_name: "research", .. })
    }),
  )
}

///|
test "Anthropic normalizes hosted tool results and search sources" {
  let response = decode_messages_response(
    {
      "content": [
        {
          "type": "server_tool_use",
          "id": "search-1",
          "name": "tool_search_tool_bm25",
          "input": Json::empty_object(),
        },
        {
          "type": "tool_search_tool_result",
          "tool_use_id": "search-1",
          "content": {
            "type": "tool_search_tool_search_result",
            "tool_references": [
              { "type": "tool_reference", "tool_name": "get_weather" },
            ],
          },
        },
        {
          "type": "web_fetch_tool_result",
          "tool_use_id": "fetch-1",
          "content": {
            "type": "web_fetch_result",
            "url": "https://example.com",
            "retrieved_at": "2026-08-05T00:00:00Z",
            "content": {
              "type": "document",
              "title": "Example",
              "source": {
                "type": "text",
                "media_type": "text/plain",
                "data": "Example Domain",
              },
            },
          },
        },
        {
          "type": "web_search_tool_result",
          "tool_use_id": "search-2",
          "content": [
            {
              "type": "web_search_result",
              "url": "https://example.com/search",
              "title": "Search result",
              "page_age": "1d",
              "encrypted_content": "cipher",
            },
          ],
        },
        {
          "type": "advisor_tool_result",
          "tool_use_id": "advisor-1",
          "content": {
            "type": "advisor_tool_result_error",
            "error_code": "unavailable",
          },
        },
      ],
    },
    id_generator=() => "source-id",
  )
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) => {
      assert_eq(result.tool_name, "tool_search_tool_bm25")
      json_inspect(result.result, content=[
        { "type": "tool_reference", "toolName": "get_weather" },
      ])
    }
    _ => fail("expected tool search result")
  }
  match response.content[2] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "type": "web_fetch_result",
        "url": "https://example.com",
        "retrievedAt": "2026-08-05T00:00:00Z",
        "content": {
          "type": "document",
          "title": "Example",
          "source": {
            "type": "text",
            "mediaType": "text/plain",
            "data": "Example Domain",
          },
        },
      })
    _ => fail("expected web fetch result")
  }
  match response.content[3] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content=[
        {
          "type": "web_search_result",
          "url": "https://example.com/search",
          "title": "Search result",
          "pageAge": "1d",
          "encryptedContent": "cipher",
        },
      ])
    _ => fail("expected web search result")
  }
  match response.content[4] {
    @provider.GeneratedSourceOutput(
      @provider.GeneratedUrlSource(url~, title~, provider_metadata~, ..)
    ) => {
      assert_eq(url, "https://example.com/search")
      assert_eq(title, Some("Search result"))
      json_inspect(provider_metadata["anthropic"], content={ "pageAge": "1d" })
    }
    _ => fail("expected web search source")
  }
  match response.content[5] {
    @provider.GeneratedToolResultOutput(result) => {
      assert_eq(result.tool_name, "advisor")
      assert_eq(result.is_error, true)
      json_inspect(result.result, content={
        "type": "advisor_tool_result_error",
        "errorCode": "unavailable",
      })
    }
    _ => fail("expected advisor result")
  }
}

///|
test "Anthropic can mark implicit code execution as dynamic" {
  let response = decode_messages_response(
    {
      "content": [
        {
          "type": "server_tool_use",
          "id": "code-1",
          "name": "code_execution",
          "input": { "code": "print(1)" },
        },
      ],
    },
    mark_code_execution_dynamic=true,
  )
  assert_eq(response.tool_calls[0].dynamic, true)
  let decoder = AnthropicStreamDecoder::new(mark_code_execution_dynamic=true)
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"server_tool_use\",\"id\":\"code-1\",\"name\":\"code_execution\",\"input\":{\"code\":\"print(1)\"}}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_stop\",\"index\":0}",
  )
  let _ = decoder.feed_line("")
  assert_eq(decoder.tool_calls[0].dynamic, true)
}

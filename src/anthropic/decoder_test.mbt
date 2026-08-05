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
    input_tokens: 17,
    output_tokens: 7,
    total_tokens: 24,
    reasoning_tokens: 2,
    cached_input_tokens: 3,
    cache_write_input_tokens: 2,
  })
  assert_eq(response.finish_reason, @provider.ToolCalls)
  let mut signature = ""
  for part in response.content {
    match part {
      @provider.GeneratedReasoningOutput(value) =>
        match value.provider_metadata.get("anthropic") {
          Some({ "signature": String(value), .. }) => signature = value
          _ => ()
        }
      _ => ()
    }
  }
  assert_eq(signature, "sig_test")
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
  assert_eq(decoder.response().text, "partial")
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
    if event is @provider.ToolCallReady(_) {
      ready = ready + 1
    }
  }
  assert_eq(ready, 0)
  assert_eq(decoder.response().finish_reason, @provider.Error)
  assert_eq(decoder.response().tool_calls.length(), 0)
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
  let response = decode_messages_response({
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
        ],
      },
    ],
  })
  assert_eq(response.content.length(), 3)
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
        provider_metadata~,
        ..
      )
    ) => {
      assert_eq(media_type, "text/plain")
      assert_eq(title, "Guide")
      json_inspect(provider_metadata["anthropic.messages"], content={
        "citedText": "A page excerpt",
        "startPageNumber": 2,
        "endPageNumber": 3,
      })
    }
    _ => fail("expected a document citation source")
  }
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
  assert_eq(decoder.response().content.length(), 1)
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
    "{\"code\":\"print(1)\",\"type\":\"programmatic-tool-call\"}",
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
  let response = decoder.response()
  assert_eq(response.finish_reason, @provider.ToolCalls)
  assert_eq(response.tool_calls.length(), 2)
  assert_eq(response.tool_calls[0].provider_executed, true)
  assert_eq(response.tool_calls[1].dynamic, true)
  assert_eq(response.content.length(), 4)
  let mut reasoning = false
  let mut results = 0
  for part in response.content {
    match part {
      @provider.GeneratedReasoningOutput(value) => {
        reasoning = true
        json_inspect(value.provider_metadata["anthropic.messages"], content={
          "redactedData": "opaque",
        })
      }
      @provider.GeneratedToolResultOutput(_) => results = results + 1
      _ => ()
    }
  }
  assert_true(reasoning)
  assert_eq(results, 1)
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

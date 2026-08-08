///|
test "official OpenAI stream emits hosted tool results and ordered content" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let decoder = @protocol.OpenResponsesStreamDecoder::new(
    provider_name="openai.responses",
    observe_events=json => hosted.observe(json),
    build_content=() => hosted.content(),
    use_built_content=true,
    has_extra_tool_calls=() => hosted.has_client_calls(),
  )
  let events : Array[@provider.StreamEvent] = []
  let feed = line => {
    let batch = decoder.feed_line(line)
    for event in batch.events {
      events.push(event)
    }
  }
  feed(
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"fs_1\",\"type\":\"file_search_call\",\"status\":\"in_progress\",\"queries\":[],\"results\":null}}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"fs_1\",\"type\":\"file_search_call\",\"status\":\"completed\",\"queries\":[\"MoonBit\"],\"results\":null}}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.output_item.added\",\"output_index\":1,\"item\":{\"id\":\"msg_1\",\"type\":\"message\",\"content\":[]}}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_1\",\"delta\":\"done\"}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.output_item.done\",\"output_index\":1,\"item\":{\"id\":\"msg_1\",\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"done\",\"annotations\":[]}]}}",
  )
  feed("")
  feed(
    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\",\"output\":[{\"id\":\"fs_1\",\"type\":\"file_search_call\",\"status\":\"completed\",\"queries\":[\"MoonBit\"],\"results\":null},{\"id\":\"msg_1\",\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"done\",\"annotations\":[]}]}],\"usage\":{\"input_tokens\":2,\"output_tokens\":1,\"total_tokens\":3}}}",
  )
  feed("")
  let mut calls = 0
  let mut results = 0
  for event in events {
    match event {
      @provider.ToolCallReady(call) if call.name == "file_search" => {
        assert_true(call.provider_executed)
        calls = calls + 1
      }
      @provider.ToolResultReady(result) if result.tool_name == "file_search" =>
        results = results + 1
      _ => ()
    }
  }
  assert_eq(calls, 1)
  assert_eq(results, 1)
  let response = decoder.response()
  assert_eq(response.content.length(), 3)
  assert_eq(response.text, "done")
  assert_eq(response.finish_reason, @provider.Stop)
}

///|
test "official OpenAI stream marks client-side provider tools as tool calls" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let decoder = @protocol.OpenResponsesStreamDecoder::new(
    observe_events=json => hosted.observe(json),
    build_content=() => hosted.content(),
    use_built_content=true,
    has_extra_tool_calls=() => hosted.has_client_calls(),
  )
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"ap_1\",\"type\":\"apply_patch_call\",\"call_id\":\"call_patch\",\"status\":\"in_progress\",\"operation\":{\"type\":\"delete_file\",\"path\":\"old.txt\"}}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"ap_1\",\"type\":\"apply_patch_call\",\"call_id\":\"call_patch\",\"status\":\"completed\",\"operation\":{\"type\":\"delete_file\",\"path\":\"old.txt\"}}}",
  )
  let done = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[{\"id\":\"ap_1\",\"type\":\"apply_patch_call\",\"call_id\":\"call_patch\",\"status\":\"completed\",\"operation\":{\"type\":\"delete_file\",\"path\":\"old.txt\"}}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}",
  )
  let completed = decoder.feed_line("")
  let mut ready = 0
  for event in done.events {
    match event {
      @provider.ToolCallReady(call) if call.name == "apply_patch" =>
        ready = ready + 1
      _ => ()
    }
  }
  assert_eq(ready, 1)
  assert_true(
    completed.events.any(event => {
      event is @provider.Finish(reason=@provider.ToolCalls, ..)
    }),
  )
  assert_eq(decoder.response().finish_reason, @provider.ToolCalls)
}

///|
test "official OpenAI stream preserves function caller metadata" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let decoder = @protocol.OpenResponsesStreamDecoder::new(
    provider_name="openai.responses",
    observe_events=json => hosted.observe(json),
    build_content=() => hosted.content(),
    use_built_content=true,
    has_extra_tool_calls=() => hosted.has_client_calls(),
    build_tool_metadata=(item_id, item) => {
      openai_responses_tool_item_metadata("openai.responses", item_id, item)
    },
  )
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"lookup\",\"arguments\":\"\"}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"lookup\",\"arguments\":\"{}\",\"namespace\":\"crm\",\"caller\":{\"type\":\"program\",\"caller_id\":\"program-1\"}}}",
  )
  let done = decoder.feed_line("")
  match done.events[0] {
    @provider.ToolCallReady(call) =>
      json_inspect(call.provider_metadata, content={
        "openai": {
          "itemId": "fc_1",
          "namespace": "crm",
          "caller": { "type": "program", "callerId": "program-1" },
        },
      })
    _ => fail("expected function tool call")
  }
}

///|
test "official OpenAI V4 stream preserves function namespace on input end" {
  let metadata = OpenAIResponsesV4StreamMetadata::new(
    "openai.responses",
    store=true,
    shell_provider_executed=false,
  )
  let part = metadata.v4_stream_part(
    @provider.ToolInputEnd("call_1"),
    Some({
      "type": "response.output_item.done",
      "output_index": 0,
      "item": {
        "id": "fc_1",
        "type": "function_call",
        "call_id": "call_1",
        "name": "lookup",
        "arguments": "{}",
        "namespace": "crm",
      },
    }),
  )
  match part {
    Some(@provider.V4ToolInputEnd(provider_metadata~, ..)) =>
      json_inspect(provider_metadata, content={
        "openai": { "namespace": "crm" },
      })
    _ => fail("expected function tool input end")
  }
}

///|
test "official OpenAI stream maps hosted tool events to custom names" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    create_openai_v4_tool_name_mapping([
      @provider.LanguageModelV4Tool::provider(
        id="openai.file_search",
        name="knowledge_base",
      ),
    ]),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let added = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "fs_1",
      "type": "file_search_call",
      "status": "in_progress",
      "queries": [],
      "results": null,
    },
  })
  match added[0] {
    @provider.ToolCallReady(call) => assert_eq(call.name, "knowledge_base")
    _ => fail("expected mapped hosted tool call")
  }
  let done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "fs_1",
      "type": "file_search_call",
      "status": "completed",
      "queries": ["MoonBit"],
      "results": null,
    },
  })
  match done[0] {
    @provider.ToolResultReady(result) =>
      assert_eq(result.tool_name, "knowledge_base")
    _ => fail("expected mapped hosted tool result")
  }
}

///|
test "official OpenAI code interpreter streams escaped code once" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let added = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "ci_1",
      "type": "code_interpreter_call",
      "container_id": "cn\"1",
      "code": null,
      "outputs": [],
    },
  })
  assert_true(added[0] is @provider.ToolInputStart(id="ci_1", ..))
  assert_true(
    added[1]
    is @provider.ToolInputDelta(
      id="ci_1",
      delta="{\"containerId\":\"cn\\\"1\",\"code\":\""
    ),
  )
  let code_delta = hosted.observe({
    "type": "response.code_interpreter_call_code.delta",
    "item_id": "ci_1",
    "output_index": 0,
    "delta": "print(\"hi\")",
  })
  assert_true(
    code_delta[0]
    is @provider.ToolInputDelta(id="ci_1", delta="print(\\\"hi\\\")"),
  )
  let code_done = hosted.observe({
    "type": "response.code_interpreter_call_code.done",
    "item_id": "ci_1",
    "output_index": 0,
    "code": "print(\"hi\")",
  })
  assert_true(code_done[0] is @provider.ToolInputDelta(id="ci_1", delta="\"}"))
  assert_true(code_done[1] is @provider.ToolInputEnd("ci_1"))
  assert_true(code_done[2] is @provider.ToolCallReady(_))
  let output_done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "ci_1",
      "type": "code_interpreter_call",
      "status": "completed",
      "container_id": "cn\"1",
      "code": "print(\"hi\")",
      "outputs": [{ "type": "logs", "logs": "ok" }],
    },
  })
  let mut ends = 0
  let mut ready = 0
  let mut results = 0
  for event in output_done {
    match event {
      @provider.ToolInputEnd(_) => ends = ends + 1
      @provider.ToolCallReady(_) => ready = ready + 1
      @provider.ToolResultReady(_) => results = results + 1
      _ => ()
    }
  }
  assert_eq(ends, 0)
  assert_eq(ready, 0)
  assert_eq(results, 1)
}

///|
test "official OpenAI apply patch closes streamed diff exactly once" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let _ = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "ap_1",
      "type": "apply_patch_call",
      "call_id": "patch-call",
      "status": "in_progress",
      "operation": { "type": "update_file", "path": "a.txt", "diff": null },
    },
  })
  let diff_delta = hosted.observe({
    "type": "response.apply_patch_call_operation_diff.delta",
    "item_id": "ap_1",
    "output_index": 0,
    "delta": "+new",
  })
  assert_true(
    diff_delta[0] is @provider.ToolInputDelta(id="patch-call", delta="+new"),
  )
  let diff_done = hosted.observe({
    "type": "response.apply_patch_call_operation_diff.done",
    "item_id": "ap_1",
    "output_index": 0,
    "diff": "+new",
  })
  assert_true(
    diff_done[0] is @provider.ToolInputDelta(id="patch-call", delta="\"}}"),
  )
  assert_true(diff_done[1] is @provider.ToolInputEnd("patch-call"))
  let output_done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "ap_1",
      "type": "apply_patch_call",
      "call_id": "patch-call",
      "status": "completed",
      "operation": { "type": "update_file", "path": "a.txt", "diff": "+new" },
    },
  })
  let mut ends = 0
  let mut ready = 0
  for event in output_done {
    match event {
      @provider.ToolInputEnd(_) => ends = ends + 1
      @provider.ToolCallReady(call) => {
        ready = ready + 1
        assert_eq(
          call.arguments,
          "{\"callId\":\"patch-call\",\"operation\":{\"type\":\"update_file\",\"path\":\"a.txt\",\"diff\":\"+new\"}}",
        )
      }
      _ => ()
    }
  }
  assert_eq(ends, 0)
  assert_eq(ready, 1)
}

///|
test "official OpenAI custom tool input deltas use the output index" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let _ = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 2,
    "item": {
      "id": "custom_1",
      "type": "custom_tool_call",
      "call_id": "custom-call",
      "name": "grep",
      "input": "",
    },
  })
  let first = hosted.observe({
    "type": "response.custom_tool_call_input.delta",
    "output_index": 2,
    "item_id": "custom_1",
    "delta": "hel",
  })
  let second = hosted.observe({
    "type": "response.custom_tool_call_input.delta",
    "output_index": 2,
    "item_id": "custom_1",
    "delta": "lo",
  })
  assert_true(
    first[0] is @provider.ToolInputDelta(id="custom-call", delta="hel"),
  )
  assert_true(
    second[0] is @provider.ToolInputDelta(id="custom-call", delta="lo"),
  )
  let done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 2,
    "item": {
      "id": "custom_1",
      "type": "custom_tool_call",
      "status": "completed",
      "call_id": "custom-call",
      "name": "grep",
      "input": "hello",
    },
  })
  assert_true(done[0] is @provider.ToolInputEnd("custom-call"))
  match done[1] {
    @provider.ToolCallReady(call) => {
      assert_eq(call.id, "custom-call")
      assert_eq(call.arguments, "\"hello\"")
    }
    _ => fail("expected custom tool call")
  }
}

///|
test "official OpenAI stream correlates approved MCP results with the pending call" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "unused-generated-id",
    approval_tool_call_ids=Map([("approval-request-1", "pending-call-1")]),
  )
  let events = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "mcp-result-1",
      "type": "mcp_call",
      "approval_request_id": "approval-request-1",
      "name": "create_short_url",
      "server_label": "zip1",
      "arguments": "{\"url\":\"https://ai-sdk.dev\"}",
      "output": "https://short.test/1",
    },
  })
  assert_eq(events.length(), 2)
  match events[0] {
    @provider.ToolCallReady(call) => assert_eq(call.id, "pending-call-1")
    _ => fail("expected correlated MCP tool call")
  }
  match events[1] {
    @provider.ToolResultReady(result) =>
      assert_eq(result.tool_call_id, "pending-call-1")
    _ => fail("expected correlated MCP tool result")
  }
}

///|
test "official OpenAI stream normalizes completed web search results" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let mapped = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "ws_1",
      "type": "web_search_call",
      "status": "completed",
      "action": {
        "type": "search",
        "query": "sf news",
        "queries": ["sf news", "bay area tech"],
        "sources": [{ "type": "url", "url": "https://example.com/news" }],
      },
    },
  })
  match mapped[0] {
    @provider.ToolResultReady(result) =>
      json_inspect(result.result, content={
        "action": {
          "type": "search",
          "query": "sf news",
          "queries": ["sf news", "bay area tech"],
        },
        "sources": [{ "type": "url", "url": "https://example.com/news" }],
      })
    _ => fail("expected streamed web search result")
  }
  let empty = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 1,
    "item": { "id": "ws_2", "type": "web_search_call", "status": "completed" },
  })
  match empty[0] {
    @provider.ToolResultReady(result) =>
      json_inspect(result.result, content=Json::empty_object())
    _ => fail("expected streamed missing-action web search result")
  }
}

///|
test "official OpenAI stream normalizes completed file search results" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let events = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "fs_1",
      "type": "file_search_call",
      "status": "completed",
      "queries": ["MoonBit"],
      "results": [
        {
          "attributes": Json::empty_object(),
          "file_id": "file-abc123",
          "filename": "moonbit.md",
          "score": 0.95,
          "text": "MoonBit is a programming language.",
        },
      ],
    },
  })
  match events[0] {
    @provider.ToolResultReady(result) =>
      json_inspect(result.result, content={
        "queries": ["MoonBit"],
        "results": [
          {
            "attributes": Json::empty_object(),
            "fileId": "file-abc123",
            "filename": "moonbit.md",
            "score": 0.95,
            "text": "MoonBit is a programming language.",
          },
        ],
      })
    _ => fail("expected streamed file search result")
  }
}

///|
test "official OpenAI stream preserves the selected web search tool name" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    create_openai_v4_tool_name_mapping([
      @provider.LanguageModelV4Tool::provider(
        id="openai.web_search_preview",
        name="preview-search",
      ),
    ]),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
    web_search_tool_name="web_search_preview",
  )
  let added = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "ws_preview",
      "type": "web_search_call",
      "status": "in_progress",
    },
  })
  assert_eq(added.length(), 3)
  assert_true(
    added[0]
    is @provider.ToolInputStart(id="ws_preview", tool_name="preview-search"),
  )
  match added[2] {
    @provider.ToolCallReady(call) => assert_eq(call.name, "preview-search")
    _ => fail("expected preview web-search call")
  }
  let done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "ws_preview",
      "type": "web_search_call",
      "status": "completed",
      "action": { "type": "search", "query": "MoonBit" },
    },
  })
  match done[0] {
    @provider.ToolResultReady(result) =>
      assert_eq(result.tool_name, "preview-search")
    _ => fail("expected preview web-search result")
  }
}

///|
test "official OpenAI stream emits complete computer tool input lifecycle" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let added = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "computer_1",
      "type": "computer_call",
      "call_id": "computer-call",
      "status": "in_progress",
      "action": { "type": "click", "button": "left", "x": 10, "y": 20 },
    },
  })
  assert_true(
    added[0]
    is @provider.ToolInputStart(id="computer-call", tool_name="computer"),
  )
  let done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "computer_1",
      "type": "computer_call",
      "call_id": "computer-call",
      "status": "completed",
      "action": { "type": "click", "button": "left", "x": 10, "y": 20 },
      "pending_safety_checks": [],
    },
  })
  assert_eq(done.length(), 3)
  match done[0] {
    @provider.ToolInputDelta(id="computer-call", delta~) =>
      json_inspect(@json.parse(delta), content={
        "actions": [{ "type": "click", "button": "left", "x": 10, "y": 20 }],
        "pendingSafetyChecks": [],
        "status": "completed",
      })
    _ => fail("expected complete computer input delta")
  }
  assert_true(done[1] is @provider.ToolInputEnd("computer-call"))
  assert_true(done[2] is @provider.ToolCallReady(_))
}

///|
test "official OpenAI stream starts client tool search input on completion" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let added = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "tool-search-item",
      "type": "tool_search_call",
      "execution": "client",
      "arguments": { "query": "MoonBit" },
    },
  })
  assert_eq(added.length(), 0)
  let done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "tool-search-item",
      "type": "tool_search_call",
      "call_id": "tool-search-call",
      "execution": "client",
      "arguments": { "query": "MoonBit" },
    },
  })
  assert_eq(done.length(), 3)
  assert_true(
    done[0]
    is @provider.ToolInputStart(id="tool-search-call", tool_name="tool_search"),
  )
  assert_true(done[1] is @provider.ToolInputEnd("tool-search-call"))
  match done[2] {
    @provider.ToolCallReady(call) => assert_eq(call.id, "tool-search-call")
    _ => fail("expected client tool-search call")
  }
}

///|
test "official OpenAI stream pairs hosted tool search output with its call" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let added = hosted.observe({
    "type": "response.output_item.added",
    "output_index": 0,
    "item": {
      "id": "hosted-search-item",
      "type": "tool_search_call",
      "call_id": "ignored-server-call-id",
      "execution": "server",
      "arguments": { "query": "MoonBit" },
    },
  })
  assert_true(
    added[0]
    is @provider.ToolInputStart(
      id="hosted-search-item",
      tool_name="tool_search"
    ),
  )
  let done = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "hosted-search-item",
      "type": "tool_search_call",
      "call_id": "ignored-server-call-id",
      "execution": "server",
      "arguments": { "query": "MoonBit" },
    },
  })
  assert_eq(done.length(), 2)
  assert_true(done[0] is @provider.ToolInputEnd("hosted-search-item"))
  match done[1] {
    @provider.ToolCallReady(call) => {
      assert_eq(call.id, "hosted-search-item")
      assert_true(call.provider_executed)
      json_inspect(@json.parse(call.arguments), content={
        "arguments": { "query": "MoonBit" },
        "call_id": null,
      })
    }
    _ => fail("expected hosted tool-search call")
  }
  let output = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 1,
    "item": {
      "id": "hosted-search-output",
      "type": "tool_search_output",
      "tools": [{ "name": "lookup" }],
    },
  })
  match output[0] {
    @provider.ToolResultReady(result) => {
      assert_eq(result.tool_call_id, "hosted-search-item")
      json_inspect(result.result, content={ "tools": [{ "name": "lookup" }] })
    }
    _ => fail("expected paired hosted tool-search output")
  }
  let content = hosted.content()
  match content[0] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.id, "hosted-search-item")
      json_inspect(@json.parse(call.arguments), content={
        "arguments": { "query": "MoonBit" },
        "call_id": null,
      })
    }
    _ => fail("expected hosted tool-search response call")
  }
  match content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      assert_eq(result.tool_call_id, "hosted-search-item")
    _ => fail("expected hosted tool-search response result")
  }
}

///|
test "official OpenAI stream emits shell calls without synthetic input events" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    id_generator=() => "generated-id",
    approval_tool_call_ids=Map([]),
  )
  let local_events = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 0,
    "item": {
      "id": "local-shell-item",
      "type": "local_shell_call",
      "call_id": "local-shell-call",
      "action": {
        "type": "exec",
        "command": ["pwd"],
        "timeout_ms": 1000,
        "working_directory": "/tmp",
      },
    },
  })
  assert_eq(local_events.length(), 1)
  match local_events[0] {
    @provider.ToolCallReady(call) =>
      json_inspect(@json.parse(call.arguments), content={
        "action": {
          "type": "exec",
          "command": ["pwd"],
          "timeoutMs": 1000,
          "workingDirectory": "/tmp",
        },
      })
    _ => fail("expected local shell call")
  }
  let shell = hosted.observe({
    "type": "response.output_item.done",
    "output_index": 1,
    "item": {
      "id": "shell-item",
      "type": "shell_call",
      "call_id": "shell-call",
      "action": {
        "commands": ["pwd"],
        "timeout_ms": 1000,
        "max_output_length": 4096,
      },
    },
  })
  assert_eq(shell.length(), 1)
  match shell[0] {
    @provider.ToolCallReady(call) =>
      json_inspect(@json.parse(call.arguments), content={
        "action": { "commands": ["pwd"] },
      })
    _ => fail("expected shell call")
  }
  let content = hosted.content()
  match content[0] {
    @provider.GeneratedToolCallOutput(call) =>
      json_inspect(@json.parse(call.arguments), content={
        "action": {
          "type": "exec",
          "command": ["pwd"],
          "timeoutMs": 1000,
          "workingDirectory": "/tmp",
        },
      })
    _ => fail("expected normalized local shell response content")
  }
}

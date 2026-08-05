///|
test "official OpenAI stream emits hosted tool results and ordered content" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    id_generator=() => "generated-id",
  )
  let decoder = @open_responses.OpenResponsesStreamDecoder::new(
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
    id_generator=() => "generated-id",
  )
  let decoder = @open_responses.OpenResponsesStreamDecoder::new(
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
test "official OpenAI stream maps hosted tool events to custom names" {
  let hosted = OpenAIResponsesHostedStreamDecoder::new(
    "openai.responses",
    create_openai_tool_name_mapping([
      @provider.ToolDefinition::provider(
        id="openai.file_search",
        name="knowledge_base",
      ),
    ]),
    id_generator=() => "generated-id",
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
    id_generator=() => "generated-id",
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
    id_generator=() => "generated-id",
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
    id_generator=() => "generated-id",
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
      assert_eq(call.arguments, "hello")
    }
    _ => fail("expected custom tool call")
  }
}

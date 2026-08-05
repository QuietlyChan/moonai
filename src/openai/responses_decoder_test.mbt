///|
test "OpenAI Responses maps complete computer tool input" {
  let response = decode_openai_responses_response({
    "id": "resp-computer",
    "status": "completed",
    "output": [
      {
        "type": "computer_call",
        "id": "computer-item-1",
        "call_id": "computer-call-1",
        "status": "completed",
        "pending_safety_checks": [
          {
            "id": "safety-1",
            "code": "confirm_action",
            "message": "Confirm this action.",
          },
        ],
        "actions": [
          { "type": "click", "button": "left", "x": 100, "y": 200 },
          {
            "type": "scroll",
            "x": 130,
            "y": 230,
            "scroll_x": 0,
            "scroll_y": 500,
          },
        ],
      },
    ],
  })
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.id, "computer-call-1")
      assert_eq(call.name, "computer")
      json_inspect(@json.parse(call.arguments), content={
        "actions": [
          { "type": "click", "button": "left", "x": 100, "y": 200 },
          { "type": "scroll", "x": 130, "y": 230, "scrollX": 0, "scrollY": 500 },
        ],
        "pendingSafetyChecks": [
          {
            "id": "safety-1",
            "code": "confirm_action",
            "message": "Confirm this action.",
          },
        ],
        "status": "completed",
      })
    }
    _ => fail("expected a computer tool call")
  }
}

///|
test "OpenAI Responses accepts the singular computer action" {
  let response = decode_openai_responses_response({
    "id": "resp-computer",
    "status": "completed",
    "output": [
      {
        "type": "computer_call",
        "id": "computer-item-1",
        "call_id": "computer-call-1",
        "status": "in_progress",
        "action": { "type": "keypress", "keys": ["CTRL", "L"] },
      },
    ],
  })
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) =>
      json_inspect(@json.parse(call.arguments), content={
        "actions": [{ "type": "keypress", "keys": ["CTRL", "L"] }],
        "pendingSafetyChecks": [],
        "status": "in_progress",
      })
    _ => fail("expected a computer tool call")
  }
}

///|
test "official OpenAI Responses decodes hosted tools in output order" {
  let response = decode_openai_responses_response({
    "id": "resp_hosted",
    "model": "gpt-5",
    "status": "completed",
    "output": [
      {
        "id": "rs_1",
        "type": "reasoning",
        "summary": [{ "type": "summary_text", "text": "checking" }],
        "encrypted_content": "opaque",
      },
      {
        "id": "ig_1",
        "type": "image_generation_call",
        "status": "completed",
        "result": "base64-image",
      },
      {
        "id": "fs_1",
        "type": "file_search_call",
        "status": "completed",
        "queries": ["MoonBit"],
        "results": null,
      },
      {
        "id": "ci_1",
        "type": "code_interpreter_call",
        "status": "completed",
        "code": "print(1)",
        "container_id": "cntr_1",
        "outputs": [{ "type": "logs", "logs": "1" }],
      },
      {
        "id": "msg_1",
        "type": "message",
        "content": [
          {
            "type": "output_text",
            "text": "done",
            "annotations": [
              {
                "type": "url_citation",
                "url": "https://moonbitlang.com",
                "title": "MoonBit",
              },
            ],
          },
        ],
      },
      {
        "id": "fc_1",
        "type": "function_call",
        "call_id": "call_1",
        "name": "lookup",
        "arguments": "{\"query\":\"MoonBit\"}",
      },
    ],
    "usage": {
      "input_tokens": 10,
      "output_tokens": 5,
      "total_tokens": 15,
      "input_tokens_details": { "cached_tokens": 2 },
      "output_tokens_details": { "reasoning_tokens": 1 },
    },
  })
  assert_eq(response.content.length(), 10)
  match response.content[0] {
    @provider.GeneratedReasoningOutput(reasoning) =>
      assert_eq(reasoning.text, "checking")
    _ => fail("expected reasoning content")
  }
  match response.content[1] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.name, "image_generation")
      assert_true(call.provider_executed)
    }
    _ => fail("expected image generation tool call")
  }
  match response.content[2] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={ "result": "base64-image" })
    _ => fail("expected image generation result")
  }
  match response.content[4] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "queries": ["MoonBit"],
        "results": null,
      })
    _ => fail("expected file search result")
  }
  match response.content[6] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "outputs": [{ "type": "logs", "logs": "1" }],
      })
    _ => fail("expected code interpreter result")
  }
  match response.content[8] {
    @provider.GeneratedSourceOutput(@provider.GeneratedUrlSource(url~, ..)) =>
      assert_eq(url, "https://moonbitlang.com")
    _ => fail("expected URL source")
  }
  assert_eq(response.text, "done")
  assert_eq(response.reasoning, "checking")
  assert_eq(response.finish_reason, @provider.ToolCalls)
  assert_eq(response.usage, {
    input_tokens: 10,
    output_tokens: 5,
    total_tokens: 15,
    reasoning_tokens: 1,
    cached_input_tokens: 2,
    cache_write_input_tokens: 0,
  })
}

///|
test "official OpenAI Responses decodes MCP approval requests" {
  let response = decode_openai_responses_response(
    {
      "id": "resp_mcp",
      "status": "completed",
      "output": [
        {
          "id": "mcpr_1",
          "type": "mcp_approval_request",
          "arguments": "{\"url\":\"https://ai-sdk.dev\"}",
          "name": "create_short_url",
          "server_label": "zip1",
        },
      ],
      "usage": { "input_tokens": 1, "output_tokens": 1, "total_tokens": 2 },
    },
    id_generator=() => "generated-tool-call",
  )
  assert_eq(response.content.length(), 2)
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.id, "generated-tool-call")
      assert_eq(call.name, "mcp.create_short_url")
      assert_true(call.provider_executed)
      assert_true(call.dynamic)
    }
    _ => fail("expected MCP tool call")
  }
  match response.content[1] {
    @provider.GeneratedToolApprovalRequestOutput(approval) => {
      assert_eq(approval.approval_id, "mcpr_1")
      assert_eq(approval.tool_call_id, "generated-tool-call")
    }
    _ => fail("expected MCP approval request")
  }
  assert_eq(response.finish_reason, @provider.Stop)
}

///|
test "official OpenAI Responses preserves phase namespace and cache writes" {
  let response = decode_openai_responses_response({
    "id": "resp_meta",
    "status": "completed",
    "output": [
      {
        "id": "msg_1",
        "type": "message",
        "phase": "commentary",
        "content": [{ "type": "output_text", "text": "working" }],
      },
      {
        "id": "fc_1",
        "type": "function_call",
        "call_id": "call_1",
        "name": "lookup",
        "arguments": "{}",
        "namespace": "weather",
      },
    ],
    "usage": {
      "input_tokens": 5,
      "output_tokens": 2,
      "total_tokens": 7,
      "input_tokens_details": { "cache_write_tokens": 3 },
    },
  })
  match response.content[0] {
    @provider.GeneratedTextOutput(text) =>
      json_inspect(text.provider_metadata, content={
        "openai": { "itemId": "msg_1", "phase": "commentary" },
      })
    _ => fail("expected text content")
  }
  match response.content[1] {
    @provider.GeneratedToolCallOutput(call) =>
      json_inspect(call.provider_metadata, content={
        "openai": { "itemId": "fc_1", "namespace": "weather" },
      })
    _ => fail("expected tool call")
  }
  assert_eq(response.usage.cache_write_input_tokens, 3)
}

///|
test "official OpenAI Responses exposes compaction encrypted metadata" {
  let response = decode_openai_responses_response({
    "id": "resp_compaction",
    "status": "completed",
    "output": [
      {
        "id": "cmp_1",
        "type": "compaction",
        "encrypted_content": "encrypted-context",
      },
    ],
    "usage": { "input_tokens": 1, "output_tokens": 1, "total_tokens": 2 },
  })
  match response.content[0] {
    @provider.GeneratedCustomOutput(custom) => {
      assert_eq(custom.kind, "openai.compaction")
      json_inspect(custom.provider_metadata, content={
        "openai": {
          "itemId": "cmp_1",
          "type": "compaction",
          "encryptedContent": "encrypted-context",
        },
      })
    }
    _ => fail("expected compaction content")
  }
}

///|
test "official OpenAI Responses maps hosted tool names back to custom names" {
  let tools = [
    @provider.ToolDefinition::provider(
      id="openai.file_search",
      name="knowledge_base",
    ),
  ]
  let response = decode_openai_responses_response(
    {
      "id": "resp_alias",
      "status": "completed",
      "output": [
        {
          "id": "fs_1",
          "type": "file_search_call",
          "status": "completed",
          "queries": ["MoonBit"],
          "results": null,
        },
      ],
    },
    tool_name_mapping=@provider_utils.create_tool_name_mapping(
      tools,
      Map([("openai.file_search", "file_search")]),
    ),
  )
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) =>
      assert_eq(call.name, "knowledge_base")
    _ => fail("expected mapped file-search call")
  }
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      assert_eq(result.tool_name, "knowledge_base")
    _ => fail("expected mapped file-search result")
  }
}

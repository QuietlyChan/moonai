///|
fn decode_test_openai_responses_response(
  json : Json,
  provider_name? : String = "openai.responses",
  shell_provider_executed? : Bool = false,
  tool_name_mapping? : @provider_utils.ToolNameMapping,
  id_generator? : @provider_utils.IdGenerator,
  approval_tool_call_ids? : Map[String, String] = Map([]),
  web_search_tool_name? : String,
) -> @provider.ChatResponse raise {
  let decoded = decode_openai_responses_response(
    json,
    provider_name~,
    shell_provider_executed~,
    tool_name_mapping=tool_name_mapping.unwrap_or(
      @provider_utils.ToolNameMapping::identity(),
    ),
    id_generator=id_generator.unwrap_or(@provider_utils.generate_id),
    approval_tool_call_ids~,
    web_search_tool_name?,
  )
  @provider.ChatResponse::from_content(
    @provider.LanguageModelV4Content::to_generated_content_array(
      decoded.content,
    ),
    decoded.usage.to_usage(),
    decoded.finish_reason.to_finish_reason(),
  ).with_diagnostics(None, decoded.response, decoded.provider_metadata, [])
}

///|
test "official OpenAI Responses reports missing output details" {
  try
    decode_test_openai_responses_response({
      "id": "resp_no_output",
      "status": "incomplete",
      "incomplete_details": { "reason": "content_filter" },
    })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_eq(message, "Responses API returned no output (content_filter)")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a missing-output error")
  }
}

///|
test "OpenAI Responses selects Azure metadata only for Azure providers" {
  let body : Json = {
    "id": "resp-provider-key",
    "status": "completed",
    "output": [
      {
        "type": "message",
        "id": "message-provider-key",
        "content": [
          { "type": "output_text", "text": "hello", "annotations": [] },
        ],
      },
    ],
  }
  let azure = decode_test_openai_responses_response(
    body,
    provider_name="azure.responses",
  )
  json_inspect(azure.provider_metadata, content={
    "azure": { "responseId": "resp-provider-key" },
  })
  match azure.content[0] {
    @provider.GeneratedTextOutput(text) =>
      json_inspect(text.provider_metadata, content={
        "azure": { "itemId": "message-provider-key" },
      })
    _ => fail("expected Azure text content")
  }
  let custom = decode_test_openai_responses_response(
    body,
    provider_name="gateway.responses",
  )
  json_inspect(custom.provider_metadata, content={
    "openai": { "responseId": "resp-provider-key" },
  })
  match custom.content[0] {
    @provider.GeneratedTextOutput(text) =>
      json_inspect(text.provider_metadata, content={
        "openai": { "itemId": "message-provider-key" },
      })
    _ => fail("expected OpenAI text content")
  }
}

///|
test "OpenAI Responses maps complete computer tool input" {
  let response = decode_test_openai_responses_response({
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
  let response = decode_test_openai_responses_response({
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
  let response = decode_test_openai_responses_response({
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
      assert_eq(call.provider_metadata.length(), 0)
    }
    _ => fail("expected image generation tool call")
  }
  match response.content[2] {
    @provider.GeneratedToolResultOutput(result) => {
      json_inspect(result.result, content={ "result": "base64-image" })
      assert_eq(result.provider_metadata.length(), 0)
    }
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
test "official OpenAI Responses normalizes web search output actions" {
  let response = decode_test_openai_responses_response({
    "id": "resp_web_search",
    "status": "completed",
    "output": [
      {
        "id": "ws_search",
        "type": "web_search_call",
        "status": "completed",
        "action": {
          "type": "search",
          "query": "sf news",
          "queries": ["sf news", "bay area tech"],
          "sources": [
            { "type": "url", "url": "https://example.com/news" },
            { "type": "api", "name": "news-index" },
          ],
        },
      },
      {
        "id": "ws_open",
        "type": "web_search_call",
        "status": "completed",
        "action": { "type": "open_page", "url": "https://example.com" },
      },
      {
        "id": "ws_find",
        "type": "web_search_call",
        "status": "completed",
        "action": {
          "type": "find_in_page",
          "url": "https://example.com",
          "pattern": "MoonBit",
        },
      },
    ],
  })
  assert_eq(response.content.length(), 6)
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "action": {
          "type": "search",
          "query": "sf news",
          "queries": ["sf news", "bay area tech"],
        },
        "sources": [
          { "type": "url", "url": "https://example.com/news" },
          { "type": "api", "name": "news-index" },
        ],
      })
    _ => fail("expected web search result")
  }
  match response.content[3] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "action": { "type": "openPage", "url": "https://example.com" },
      })
    _ => fail("expected open-page result")
  }
  match response.content[5] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "action": {
          "type": "findInPage",
          "url": "https://example.com",
          "pattern": "MoonBit",
        },
      })
    _ => fail("expected find-in-page result")
  }
}

///|
test "official OpenAI Responses normalizes file search results" {
  let response = decode_test_openai_responses_response({
    "id": "resp_file_search",
    "status": "completed",
    "output": [
      {
        "id": "fs_results",
        "type": "file_search_call",
        "status": "completed",
        "queries": ["MoonBit"],
        "results": [
          {
            "attributes": { "language": "en" },
            "file_id": "file-abc123",
            "filename": "moonbit.md",
            "score": 0.95,
            "text": "MoonBit is a programming language.",
          },
        ],
      },
      {
        "id": "fs_missing_results",
        "type": "file_search_call",
        "status": "completed",
        "queries": ["AI SDK"],
      },
    ],
  })
  assert_eq(response.content.length(), 4)
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "queries": ["MoonBit"],
        "results": [
          {
            "attributes": { "language": "en" },
            "fileId": "file-abc123",
            "filename": "moonbit.md",
            "score": 0.95,
            "text": "MoonBit is a programming language.",
          },
        ],
      })
    _ => fail("expected file search result")
  }
  match response.content[3] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "queries": ["AI SDK"],
        "results": null,
      })
    _ => fail("expected missing-results file search result")
  }
}

///|
test "official OpenAI Responses JSON-encodes custom tool input" {
  let response = decode_test_openai_responses_response({
    "id": "resp_custom_tool",
    "status": "completed",
    "output": [
      {
        "id": "ct_1",
        "type": "custom_tool_call",
        "call_id": "call_custom_1",
        "name": "write_sql",
        "input": "SELECT * FROM users",
      },
    ],
  })
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.arguments, "\"SELECT * FROM users\"")
      json_inspect(@json.parse(call.arguments), content="SELECT * FROM users")
    }
    _ => fail("expected custom tool call")
  }
}

///|
test "official OpenAI Responses preserves empty reasoning items" {
  let response = decode_test_openai_responses_response({
    "id": "resp_empty_reasoning",
    "status": "completed",
    "output": [
      {
        "id": "rs_1",
        "type": "reasoning",
        "summary": [],
        "encrypted_content": null,
      },
    ],
  })
  assert_eq(response.content.length(), 1)
  match response.content[0] {
    @provider.GeneratedReasoningOutput(reasoning) => {
      assert_eq(reasoning.text, "")
      json_inspect(reasoning.provider_metadata, content={
        "openai": { "itemId": "rs_1", "reasoningEncryptedContent": null },
      })
    }
    _ => fail("expected empty reasoning content")
  }
}

///|
test "official OpenAI Responses omits null MCP output fields" {
  let response = decode_test_openai_responses_response({
    "id": "resp_mcp_null",
    "status": "completed",
    "output": [
      {
        "id": "mcp_1",
        "type": "mcp_call",
        "name": "lookup",
        "server_label": "server-1",
        "arguments": "{}",
        "output": null,
        "error": null,
      },
    ],
  })
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content={
        "type": "call",
        "serverLabel": "server-1",
        "name": "lookup",
        "arguments": "{}",
      })
    _ => fail("expected MCP result")
  }
}

///|
test "official OpenAI Responses preserves text annotations in provider metadata" {
  let response = decode_test_openai_responses_response({
    "id": "resp_annotations",
    "status": "completed",
    "output": [
      {
        "id": "msg_1",
        "type": "message",
        "phase": "final_answer",
        "content": [
          {
            "type": "output_text",
            "text": "See the document.",
            "annotations": [
              {
                "type": "file_citation",
                "file_id": "file_1",
                "filename": "notes.txt",
                "index": 4,
              },
            ],
          },
        ],
      },
    ],
  })
  assert_eq(response.content.length(), 2)
  match response.content[0] {
    @provider.GeneratedTextOutput(text) =>
      json_inspect(text.provider_metadata, content={
        "openai": {
          "itemId": "msg_1",
          "phase": "final_answer",
          "annotations": [
            {
              "type": "file_citation",
              "file_id": "file_1",
              "filename": "notes.txt",
              "index": 4,
            },
          ],
        },
      })
    _ => fail("expected annotated text")
  }
  match response.content[1] {
    @provider.GeneratedSourceOutput(
      @provider.GeneratedDocumentSource(provider_metadata~, ..)
    ) =>
      json_inspect(provider_metadata, content={
        "openai": { "type": "file_citation", "fileId": "file_1", "index": 4 },
      })
    _ => fail("expected file citation source")
  }
}

///|
test "official OpenAI Responses keeps web search results without an action" {
  let response = decode_test_openai_responses_response({
    "id": "resp_web_search_empty",
    "status": "completed",
    "output": [
      { "id": "ws_missing", "type": "web_search_call", "status": "completed" },
      {
        "id": "ws_null",
        "type": "web_search_call",
        "status": "completed",
        "action": null,
      },
    ],
  })
  assert_eq(response.content.length(), 4)
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.id, "ws_missing")
      assert_eq(call.name, "web_search")
    }
    _ => fail("expected missing-action web search call")
  }
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content=Json::empty_object())
    _ => fail("expected missing-action web search result")
  }
  match response.content[3] {
    @provider.GeneratedToolResultOutput(result) =>
      json_inspect(result.result, content=Json::empty_object())
    _ => fail("expected null-action web search result")
  }
}

///|
test "official OpenAI Responses preserves the selected web search tool name" {
  let mapping = create_openai_v4_tool_name_mapping([
    @provider.LanguageModelV4Tool::provider(
      id="openai.web_search_preview",
      name="preview-search",
    ),
  ])
  let response = decode_test_openai_responses_response(
    {
      "id": "resp_web_search_preview",
      "status": "completed",
      "output": [
        {
          "id": "ws_preview",
          "type": "web_search_call",
          "status": "completed",
          "action": { "type": "search", "query": "MoonBit" },
        },
      ],
    },
    tool_name_mapping=mapping,
    web_search_tool_name="web_search_preview",
  )
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) =>
      assert_eq(call.name, "preview-search")
    _ => fail("expected preview web-search call")
  }
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) =>
      assert_eq(result.tool_name, "preview-search")
    _ => fail("expected preview web-search result")
  }
}

///|
test "official OpenAI Responses decodes MCP approval requests" {
  let response = decode_test_openai_responses_response(
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
      assert_eq(call.provider_metadata["openai"], {
        "approvalRequestId": "mcpr_1",
      })
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
test "official OpenAI Responses correlates approved MCP results with the pending call" {
  let response = decode_test_openai_responses_response(
    {
      "id": "resp_mcp_result",
      "status": "completed",
      "output": [
        {
          "id": "mcp_result_1",
          "type": "mcp_call",
          "approval_request_id": "mcpr_1",
          "arguments": "{\"url\":\"https://ai-sdk.dev\"}",
          "name": "create_short_url",
          "server_label": "zip1",
          "output": "https://short.test/1",
        },
      ],
      "usage": { "input_tokens": 1, "output_tokens": 1, "total_tokens": 2 },
    },
    approval_tool_call_ids=Map([("mcpr_1", "generated-tool-call")]),
  )
  assert_eq(response.content.length(), 2)
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.id, "generated-tool-call")
      assert_eq(call.provider_metadata.length(), 0)
    }
    _ => fail("expected correlated MCP tool call")
  }
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) => {
      assert_eq(result.tool_call_id, "generated-tool-call")
      assert_eq(result.provider_metadata["openai"], { "itemId": "mcp_result_1" })
    }
    _ => fail("expected correlated MCP tool result")
  }
}

///|
test "official OpenAI Responses preserves phase namespace and cache writes" {
  let response = decode_test_openai_responses_response({
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
        "caller": { "type": "program", "caller_id": "program-1" },
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
        "openai": {
          "itemId": "fc_1",
          "namespace": "weather",
          "caller": { "type": "program", "callerId": "program-1" },
        },
      })
    _ => fail("expected tool call")
  }
  assert_eq(response.usage.cache_write_input_tokens, 3)
}

///|
test "official OpenAI Responses exposes compaction encrypted metadata" {
  let response = decode_test_openai_responses_response({
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
  let response = decode_test_openai_responses_response(
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

///|
test "OpenAI Responses marks container shell calls as provider executed" {
  let response = decode_test_openai_responses_response(
    {
      "id": "resp-shell",
      "status": "completed",
      "output": [
        {
          "type": "shell_call",
          "id": "shell-item",
          "call_id": "shell-call",
          "action": {
            "commands": ["pwd"],
            "timeout_ms": 1000,
            "max_output_length": 4096,
          },
        },
      ],
    },
    shell_provider_executed=true,
  )
  match response.content[0] {
    @provider.GeneratedToolCallOutput(call) => {
      assert_eq(call.provider_executed, true)
      assert_eq(call.provider_metadata["openai"], { "itemId": "shell-item" })
      json_inspect(@json.parse(call.arguments), content={
        "action": { "commands": ["pwd"] },
      })
    }
    _ => fail("expected shell tool call")
  }
}

///|
test "OpenAI Responses normalizes shell exit codes" {
  let response = decode_test_openai_responses_response({
    "id": "resp-shell-output",
    "status": "completed",
    "output": [
      {
        "type": "shell_call_output",
        "id": "shell-output-item",
        "call_id": "shell-call",
        "output": [
          {
            "stdout": "done",
            "stderr": "",
            "outcome": { "type": "exit", "exit_code": 0 },
          },
          {
            "stdout": "",
            "stderr": "timed out",
            "outcome": { "type": "timeout" },
          },
        ],
      },
    ],
  })
  match response.content[0] {
    @provider.GeneratedToolResultOutput(result) => {
      json_inspect(result.result, content={
        "output": [
          {
            "stdout": "done",
            "stderr": "",
            "outcome": { "type": "exit", "exitCode": 0 },
          },
          {
            "stdout": "",
            "stderr": "timed out",
            "outcome": { "type": "timeout" },
          },
        ],
      })
      assert_eq(result.provider_metadata.length(), 0)
    }
    _ => fail("expected shell result")
  }
}

///|
test "Anthropic Messages response schema accepts a valid envelope" {
  validate_anthropic_messages_response({
    "type": "message",
    "id": "msg-valid",
    "model": "claude-sonnet-4-6",
    "content": [
      { "type": "thinking", "thinking": "plan", "signature": "sig" },
      { "type": "text", "text": "answer" },
      {
        "type": "tool_use",
        "id": "call-1",
        "name": "lookup",
        "input": { "query": "MoonBit" },
      },
    ],
    "stop_reason": "tool_use",
    "usage": { "input_tokens": 3, "output_tokens": 2 },
  })
}

///|
test "Anthropic Messages response schema rejects invalid envelope fields" {
  let invalid_responses : Array[Json] = [
    {
      "content": [{ "type": "text", "text": "missing message type" }],
      "usage": { "input_tokens": 1, "output_tokens": 1 },
    },
    {
      "type": "message",
      "content": [{ "type": "thinking", "thinking": "missing signature" }],
      "usage": { "input_tokens": 1, "output_tokens": 1 },
    },
    {
      "type": "message",
      "content": [{ "type": "text", "text": "missing usage output" }],
      "usage": { "input_tokens": 1 },
    },
  ]
  for response in invalid_responses {
    try validate_anthropic_messages_response(response) catch {
      @provider.InvalidResponseDataError(message~, data~) => {
        assert_true(message.has_prefix("Invalid Anthropic Messages response"))
        assert_eq(data, response)
      }
      error => fail("unexpected Anthropic response schema error: \{error}")
    } noraise {
      _ => fail("expected Anthropic response schema validation to fail")
    }
  }
}

///|
test "Anthropic Messages response schema accepts current provider block families" {
  validate_anthropic_messages_response({
    "type": "message",
    "id": null,
    "model": "claude-sonnet-4-6",
    "content": [
      {
        "type": "text",
        "text": "cited",
        "citations": [
          {
            "type": "web_search_result_location",
            "cited_text": "web quote",
            "url": "https://example.com",
            "title": "Example",
            "encrypted_index": "enc",
          },
          {
            "type": "page_location",
            "cited_text": "page quote",
            "document_index": 0,
            "document_title": null,
            "start_page_number": 1,
            "end_page_number": 2,
          },
          {
            "type": "char_location",
            "cited_text": "character quote",
            "document_index": 1,
            "document_title": "Reference",
            "start_char_index": 3,
            "end_char_index": 12,
          },
        ],
      },
      { "type": "redacted_thinking", "data": "opaque" },
      { "type": "compaction", "content": "summary" },
      {
        "type": "tool_use",
        "id": "client-1",
        "name": "lookup",
        "input": { "query": "MoonBit" },
        "caller": {
          "type": "code_execution_20250825",
          "tool_id": "server-code",
        },
      },
      {
        "type": "server_tool_use",
        "id": "server-code",
        "name": "code_execution",
        "input": null,
        "caller": { "type": "direct" },
      },
      {
        "type": "mcp_tool_use",
        "id": "mcp-1",
        "name": "search",
        "input": { "q": "MoonBit" },
        "server_name": "docs",
      },
      {
        "type": "mcp_tool_result",
        "tool_use_id": "mcp-1",
        "is_error": false,
        "content": ["ok", { "type": "text", "text": "done" }],
      },
      {
        "type": "web_fetch_tool_result",
        "tool_use_id": "fetch-1",
        "content": {
          "type": "web_fetch_result",
          "url": "https://moonbitlang.com/docs",
          "retrieved_at": "2026-08-07T00:00:00Z",
          "content": {
            "type": "document",
            "title": null,
            "citations": { "enabled": true },
            "source": {
              "type": "text",
              "media_type": "text/plain",
              "data": "MoonBit docs",
            },
          },
        },
      },
      {
        "type": "web_search_tool_result",
        "tool_use_id": "search-1",
        "content": [
          {
            "type": "web_search_result",
            "url": "https://moonbitlang.com",
            "title": "MoonBit",
            "encrypted_content": "cipher",
            "page_age": null,
          },
        ],
      },
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "code-1",
        "content": {
          "type": "encrypted_code_execution_result",
          "encrypted_stdout": "ciphertext",
          "stderr": "",
          "return_code": 0,
          "content": [{ "type": "code_execution_output", "file_id": "file-1" }],
        },
      },
      {
        "type": "bash_code_execution_tool_result",
        "tool_use_id": "bash-1",
        "content": {
          "type": "bash_code_execution_result",
          "content": [
            { "type": "bash_code_execution_output", "file_id": "file-2" },
          ],
          "stdout": "ok",
          "stderr": "",
          "return_code": 0,
        },
      },
      {
        "type": "text_editor_code_execution_tool_result",
        "tool_use_id": "editor-1",
        "content": {
          "type": "text_editor_code_execution_str_replace_result",
          "lines": ["updated"],
          "new_lines": 1,
          "new_start": 2,
          "old_lines": null,
          "old_start": null,
        },
      },
      {
        "type": "tool_search_tool_result",
        "tool_use_id": "discover-1",
        "content": {
          "type": "tool_search_tool_search_result",
          "tool_references": [
            { "type": "tool_reference", "tool_name": "get_weather" },
          ],
        },
      },
      {
        "type": "advisor_tool_result",
        "tool_use_id": "advisor-1",
        "content": {
          "type": "advisor_redacted_result",
          "encrypted_content": "advisor-cipher",
        },
      },
      { "type": "fallback" },
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "stop_details": {
      "type": "model_context_window_exceeded",
      "category": null,
      "explanation": "Use a larger model",
      "recommended_model": "claude-opus-5",
    },
    "usage": {
      "input_tokens": 10,
      "output_tokens": 5,
      "output_tokens_details": { "thinking_tokens": null },
      "cache_creation_input_tokens": null,
      "cache_read_input_tokens": 2,
      "iterations": [
        {
          "type": "fallback_message",
          "model": null,
          "input_tokens": 4,
          "output_tokens": 2,
          "cache_creation_input_tokens": null,
          "cache_read_input_tokens": 1,
        },
      ],
    },
    "container": {
      "expires_at": "2026-08-08T00:00:00Z",
      "id": "container-1",
      "skills": [{ "type": "custom", "skill_id": "skill-1", "version": "1" }],
    },
    "context_management": {
      "applied_edits": [
        {
          "type": "clear_tool_uses_20250919",
          "cleared_tool_uses": 1,
          "cleared_input_tokens": 20,
        },
        {
          "type": "clear_thinking_20251015",
          "cleared_thinking_turns": 1,
          "cleared_input_tokens": 10,
        },
        { "type": "compact_20260112" },
      ],
    },
  })
}

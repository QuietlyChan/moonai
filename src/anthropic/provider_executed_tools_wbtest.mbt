///|
test "Anthropic code execution factories expose versioned schemas" {
  let legacy = codeExecution_20250522()
  assert_true(legacy.is_provider_executed())
  assert_true(!legacy.supports_deferred_results())
  assert_true(
    @provider_utils.json_schema_matches(legacy.input_schema().unwrap(), {
      "code": "print('moonbit')",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(legacy.output_schema().unwrap(), {
      "type": "code_execution_result",
      "stdout": "moonbit\n",
      "stderr": "",
      "return_code": 0,
    }),
  )
  match legacy.to_tool_definition("python") {
    @provider.ProviderTool(id~, args~, ..) => {
      assert_eq(id, "anthropic.code_execution_20250522")
      assert_eq(args, Json::empty_object())
    }
    _ => fail("expected provider-executed code tool")
  }
  let previous = code_execution_20250825()
  let current = code_execution_20260120()
  for tool in [previous, current] {
    assert_true(tool.is_provider_executed())
    assert_true(tool.supports_deferred_results())
    assert_true(
      @provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
        "type": "programmatic-tool-call",
        "code": "result = await tools.weather({})",
      }),
    )
    assert_true(
      @provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
        "type": "bash_code_execution",
        "command": "ls",
      }),
    )
    assert_true(
      @provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
        "type": "text_editor_code_execution",
        "command": "str_replace",
        "path": "/workspace/main.mbt",
        "old_str": "old",
        "new_str": "new",
      }),
    )
  }
  let encrypted : Json = {
    "type": "encrypted_code_execution_result",
    "encrypted_stdout": "ciphertext",
    "stderr": "",
    "return_code": 0,
  }
  assert_true(
    !@provider_utils.json_schema_matches(
      previous.output_schema().unwrap(),
      encrypted,
    ),
  )
  assert_true(
    @provider_utils.json_schema_matches(
      current.output_schema().unwrap(),
      encrypted,
    ),
  )
  assert_true(
    @provider_utils.json_schema_matches(current.output_schema().unwrap(), {
      "type": "text_editor_code_execution_view_result",
      "content": "line one",
      "file_type": "text",
      "num_lines": 1,
      "start_line": 1,
      "total_lines": 1,
    }),
  )
}

///|
test "Anthropic web tool factories preserve SDK argument shapes" {
  let fetch = webFetch_20250910(
    max_uses=3,
    allowed_domains=["moonbitlang.com"],
    blocked_domains=["example.com"],
    citations=AnthropicWebFetchCitations::new(enabled=true),
    max_content_tokens=4096,
  )
  assert_true(fetch.is_provider_executed())
  assert_true(fetch.supports_deferred_results())
  assert_true(
    @provider_utils.json_schema_matches(fetch.input_schema().unwrap(), {
      "url": "https://moonbitlang.com/docs",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(fetch.output_schema().unwrap(), {
      "type": "web_fetch_result",
      "url": "https://moonbitlang.com/docs",
      "content": {
        "type": "document",
        "title": "MoonBit Docs",
        "source": {
          "type": "text",
          "mediaType": "text/plain",
          "data": "MoonBit",
        },
      },
      "retrievedAt": "2026-08-07T00:00:00Z",
    }),
  )
  match fetch.to_tool_definition("fetcher") {
    @provider.ProviderTool(id~, args~, ..) => {
      assert_eq(id, "anthropic.web_fetch_20250910")
      assert_eq(args, {
        "maxUses": 3,
        "allowedDomains": ["moonbitlang.com"],
        "blockedDomains": ["example.com"],
        "citations": { "enabled": true },
        "maxContentTokens": 4096,
      })
    }
    _ => fail("expected provider-executed web fetch tool")
  }
  let search = webSearch_20260209(
    max_uses=5,
    allowed_domains=["moonbitlang.com"],
    user_location=AnthropicWebSearchUserLocation::new(
      city="Shanghai",
      country="CN",
      timezone="Asia/Shanghai",
    ),
  )
  assert_true(search.is_provider_executed())
  assert_true(search.supports_deferred_results())
  assert_true(
    @provider_utils.json_schema_matches(search.input_schema().unwrap(), {
      "query": "MoonBit AI SDK",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(search.output_schema().unwrap(), [
      {
        "type": "web_search_result",
        "url": "https://moonbitlang.com",
        "title": "MoonBit",
        "pageAge": null,
        "encryptedContent": "opaque",
      },
    ]),
  )
  match search.to_tool_definition("searcher") {
    @provider.ProviderTool(id~, args~, ..) => {
      assert_eq(id, "anthropic.web_search_20260209")
      assert_eq(args, {
        "maxUses": 5,
        "allowedDomains": ["moonbitlang.com"],
        "userLocation": {
          "type": "approximate",
          "city": "Shanghai",
          "country": "CN",
          "timezone": "Asia/Shanghai",
        },
      })
    }
    _ => fail("expected provider-executed web search tool")
  }
}

///|
test "Anthropic tool search factories distinguish regex and BM25 input" {
  let regex = toolSearchRegex_20251119()
  let bm25 = toolSearchBm25_20251119()
  for tool in [regex, bm25] {
    assert_true(tool.is_provider_executed())
    assert_true(tool.supports_deferred_results())
    assert_true(
      @provider_utils.json_schema_matches(tool.output_schema().unwrap(), [
        { "type": "tool_reference", "toolName": "get_weather" },
      ]),
    )
  }
  assert_true(
    @provider_utils.json_schema_matches(regex.input_schema().unwrap(), {
      "pattern": "get_.*_data",
      "limit": 4,
    }),
  )
  assert_true(
    !@provider_utils.json_schema_matches(regex.input_schema().unwrap(), {
      "query": "weather data",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(bm25.input_schema().unwrap(), {
      "query": "weather data",
    }),
  )
  match regex.to_tool_definition("toolSearch") {
    @provider.ProviderTool(id~, args~, ..) => {
      assert_eq(id, "anthropic.tool_search_regex_20251119")
      assert_eq(args, Json::empty_object())
    }
    _ => fail("expected provider-executed tool search")
  }
}

///|
test "Anthropic provider-executed tool args become snake-case wire fields" {
  let fetch = web_fetch_20260209(
    max_uses=2,
    allowed_domains=["moonbitlang.com"],
    citations=AnthropicWebFetchCitations::new(enabled=true),
    max_content_tokens=2048,
  )
  let search = web_search_20250305(
    max_uses=3,
    blocked_domains=["example.com"],
    user_location=AnthropicWebSearchUserLocation::new(
      region="Shanghai",
      country="CN",
    ),
  )
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[
            @provider.V4PromptText(
              text="Research MoonBit.",
              provider_options=Map([]),
            ),
          ],
          provider_options=Map([]),
        ),
      ]),
      tools=[
        @provider.LanguageModelV4Tool::from_tool_definition(
          fetch.to_tool_definition("fetch"),
        ),
        @provider.LanguageModelV4Tool::from_tool_definition(
          search.to_tool_definition("search"),
        ),
        @provider.LanguageModelV4Tool::from_tool_definition(
          tool_search_bm25_20251119().to_tool_definition("discover"),
        ),
        @provider.LanguageModelV4Tool::from_tool_definition(
          code_execution_20250522().to_tool_definition("python"),
        ),
      ],
    ),
    "anthropic.messages",
    false,
  )
  assert_true(
    prepared.body
    is {
      "tools": [
        {
          "type": "web_fetch_20260209",
          "name": "web_fetch",
          "max_uses": 2,
          "allowed_domains": ["moonbitlang.com"],
          "citations": { "enabled": true, .. },
          "max_content_tokens": 2048,
          ..
        },
        {
          "type": "web_search_20250305",
          "name": "web_search",
          "max_uses": 3,
          "blocked_domains": ["example.com"],
          "user_location": {
            "type": "approximate",
            "region": "Shanghai",
            "country": "CN",
            ..
          },
          ..
        },
        {
          "type": "tool_search_tool_bm25_20251119",
          "name": "tool_search_tool_bm25",
          ..
        },
        { "type": "code_execution_20250522", "name": "code_execution", .. },
      ],
      ..
    },
  )
  assert_true(
    prepared.beta_features.contains("code-execution-web-tools-2026-02-09"),
  )
  assert_true(prepared.beta_features.contains("code-execution-2025-05-22"))
}

///|
test "Anthropic V4 replays provider-executed results with native blocks" {
  let fetch = web_fetch_20260209()
  let search = web_search_20260209()
  let discover = tool_search_regex_20251119()
  let code = code_execution_20260120()
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="fetch-1",
            tool_name="fetch",
            input={ "url": "https://moonbitlang.com" },
            provider_executed=true,
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="fetch-1",
            tool_name="fetch",
            value={
              "type": "web_fetch_result",
              "url": "https://moonbitlang.com",
              "content": {
                "type": "document",
                "title": "MoonBit",
                "source": {
                  "type": "text",
                  "mediaType": "text/plain",
                  "data": "MoonBit",
                },
              },
              "retrievedAt": null,
            },
          ),
        ),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="search-1",
            tool_name="search",
            input={ "query": "MoonBit" },
            provider_executed=true,
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="search-1",
            tool_name="search",
            value=[
              {
                "type": "web_search_result",
                "url": "https://moonbitlang.com",
                "title": "MoonBit",
                "pageAge": null,
                "encryptedContent": "cipher",
              },
            ],
          ),
        ),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="discover-1",
            tool_name="discover",
            input={ "pattern": "weather" },
            provider_executed=true,
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="discover-1",
            tool_name="discover",
            value=[{ "type": "tool_reference", "toolName": "get_weather" }],
          ),
        ),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="code-1",
            tool_name="code",
            input={ "type": "bash_code_execution", "command": "pwd" },
            provider_executed=true,
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="code-1",
            tool_name="code",
            value={
              "type": "bash_code_execution_result",
              "content": [],
              "stdout": "/workspace\n",
              "stderr": "",
              "return_code": 0,
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(prompt, tools=[
      @provider.LanguageModelV4Tool::from_tool_definition(
        fetch.to_tool_definition("fetch"),
      ),
      @provider.LanguageModelV4Tool::from_tool_definition(
        search.to_tool_definition("search"),
      ),
      @provider.LanguageModelV4Tool::from_tool_definition(
        discover.to_tool_definition("discover"),
      ),
      @provider.LanguageModelV4Tool::from_tool_definition(
        code.to_tool_definition("code"),
      ),
    ]),
    "anthropic.messages",
    false,
  )
  guard prepared.body
    is {
      "messages": [{ "role": "assistant", "content": Array(content), .. }],
      ..
    } else {
    fail("expected one Anthropic assistant message")
  }
  assert_eq(content.length(), 8)
  assert_true(
    content[0]
    is { "type": "server_tool_use", "id": "fetch-1", "name": "web_fetch", .. },
  )
  assert_true(
    content[1]
    is {
      "type": "web_fetch_tool_result",
      "tool_use_id": "fetch-1",
      "content": {
        "type": "web_fetch_result",
        "retrieved_at": Null,
        "content": { "source": { "media_type": "text/plain", .. }, .. },
        ..
      },
      ..
    },
  )
  assert_true(
    content[2]
    is { "type": "server_tool_use", "id": "search-1", "name": "web_search", .. },
  )
  assert_true(
    content[3]
    is {
      "type": "web_search_tool_result",
      "tool_use_id": "search-1",
      "content": [
        {
          "type": "web_search_result",
          "page_age": Null,
          "encrypted_content": "cipher",
          ..
        },
      ],
      ..
    },
  )
  assert_true(
    content[4]
    is {
      "type": "server_tool_use",
      "id": "discover-1",
      "name": "tool_search_tool_regex",
      ..
    },
  )
  assert_true(
    content[5]
    is {
      "type": "tool_search_tool_result",
      "tool_use_id": "discover-1",
      "content": {
        "type": "tool_search_tool_search_result",
        "tool_references": [
          { "type": "tool_reference", "tool_name": "get_weather", .. },
        ],
        ..
      },
      ..
    },
  )
  assert_true(
    content[6]
    is {
      "type": "server_tool_use",
      "id": "code-1",
      "name": "bash_code_execution",
      ..
    },
  )
  assert_true(
    content[7]
    is {
      "type": "bash_code_execution_tool_result",
      "tool_use_id": "code-1",
      "content": { "type": "bash_code_execution_result", "return_code": 0, .. },
      ..
    },
  )
  assert_eq(prepared.warnings.length(), 0)
}

///|
test "Anthropic decoder preserves extended code execution result fields" {
  let response = decode_messages_response({
    "content": [
      {
        "type": "server_tool_use",
        "id": "code-1",
        "name": "bash_code_execution",
        "input": { "command": "pwd" },
      },
      {
        "type": "bash_code_execution_tool_result",
        "tool_use_id": "code-1",
        "content": {
          "type": "bash_code_execution_tool_result_error",
          "error_code": "unavailable",
        },
      },
      {
        "type": "text_editor_code_execution_tool_result",
        "tool_use_id": "code-2",
        "content": {
          "type": "text_editor_code_execution_view_result",
          "content": "line one",
          "file_type": "text",
          "num_lines": 1,
          "start_line": 1,
          "total_lines": 1,
        },
      },
    ],
  })
  match response.content[1] {
    @provider.GeneratedToolResultOutput(result) => {
      assert_true(result.is_error)
      assert_eq(result.result, {
        "type": "bash_code_execution_tool_result_error",
        "error_code": "unavailable",
      })
    }
    _ => fail("expected bash code execution result")
  }
  match response.content[2] {
    @provider.GeneratedToolResultOutput(result) =>
      assert_eq(result.result, {
        "type": "text_editor_code_execution_view_result",
        "content": "line one",
        "file_type": "text",
        "num_lines": 1,
        "start_line": 1,
        "total_lines": 1,
      })
    _ => fail("expected text editor code execution result")
  }
}

///|
test "Anthropic V4 maps every code execution result family to native blocks" {
  let warnings : Array[@provider.Warning] = []
  let standard = @provider.LanguageModelV4ToolResultPart::json(
    tool_call_id="code-standard",
    tool_name="code_execution",
    value={
      "type": "code_execution_result",
      "stdout": "ok\n",
      "stderr": "",
      "return_code": 0,
      "content": [{ "type": "code_execution_output", "file_id": "file-1" }],
    },
  )
  assert_eq(
    anthropic_v4_provider_tool_result(standard, "code_execution", warnings),
    Some({
      "type": "code_execution_tool_result",
      "tool_use_id": "code-standard",
      "content": {
        "type": "code_execution_result",
        "stdout": "ok\n",
        "stderr": "",
        "return_code": 0,
        "content": [{ "type": "code_execution_output", "file_id": "file-1" }],
      },
    }),
  )
  let encrypted = @provider.LanguageModelV4ToolResultPart::json(
    tool_call_id="code-encrypted",
    tool_name="code_execution",
    value={
      "type": "encrypted_code_execution_result",
      "encrypted_stdout": "ciphertext",
      "stderr": "",
      "return_code": 0,
    },
  )
  assert_true(
    anthropic_v4_provider_tool_result(encrypted, "code_execution", warnings)
    is Some(
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "code-encrypted",
        "content": {
          "type": "encrypted_code_execution_result",
          "encrypted_stdout": "ciphertext",
          "content": [],
          ..
        },
        ..
      }
    ),
  )
  let bash = @provider.LanguageModelV4ToolResultPart::json(
    tool_call_id="code-bash",
    tool_name="code_execution",
    value={
      "type": "bash_code_execution_result",
      "content": [],
      "stdout": "/workspace\n",
      "stderr": "",
      "return_code": 0,
    },
  )
  assert_true(
    anthropic_v4_provider_tool_result(bash, "code_execution", warnings)
    is Some(
      {
        "type": "bash_code_execution_tool_result",
        "tool_use_id": "code-bash",
        ..
      }
    ),
  )
  let editor = @provider.LanguageModelV4ToolResultPart::json(
    tool_call_id="code-editor",
    tool_name="code_execution",
    value={
      "type": "text_editor_code_execution_create_result",
      "is_file_update": true,
    },
  )
  assert_true(
    anthropic_v4_provider_tool_result(editor, "code_execution", warnings)
    is Some(
      {
        "type": "text_editor_code_execution_tool_result",
        "tool_use_id": "code-editor",
        ..
      }
    ),
  )
  let legacy_error = @provider.LanguageModelV4ToolResultPart::error_json(
    tool_call_id="code-error",
    tool_name="code_execution",
    value={
      "type": "code_execution_tool_result_error",
      "errorCode": "unavailable",
    },
  )
  assert_true(
    anthropic_v4_provider_tool_result(legacy_error, "code_execution", warnings)
    is Some(
      {
        "type": "code_execution_tool_result",
        "content": {
          "type": "code_execution_tool_result_error",
          "error_code": "unavailable",
          ..
        },
        ..
      }
    ),
  )
  let text_error = @provider.LanguageModelV4ToolResultPart::error_text(
    tool_call_id="code-text-error",
    tool_name="code_execution",
    value="failed",
  )
  assert_true(
    anthropic_v4_provider_tool_result(text_error, "code_execution", warnings)
    is Some(
      {
        "type": "bash_code_execution_tool_result",
        "content": { "error_code": "unknown", .. },
        ..
      }
    ),
  )
  let unsupported = @provider.LanguageModelV4ToolResultPart::text(
    tool_call_id="code-text",
    tool_name="code_execution",
    value="plain text",
  )
  assert_eq(
    anthropic_v4_provider_tool_result(unsupported, "code_execution", warnings),
    None,
  )
  assert_eq(warnings.length(), 1)
}

///|
test "Anthropic V4 maps web and tool-search provider results and errors" {
  let warnings : Array[@provider.Warning] = []
  let fetch = @provider.LanguageModelV4ToolResultPart::json(
    tool_call_id="fetch-1",
    tool_name="web_fetch",
    value={
      "type": "web_fetch_result",
      "url": "https://moonbitlang.com/docs",
      "content": {
        "type": "document",
        "title": "MoonBit",
        "citations": { "enabled": true },
        "source": {
          "type": "text",
          "mediaType": "text/plain",
          "data": "MoonBit docs",
        },
      },
      "retrievedAt": "2026-08-07T00:00:00Z",
    },
  )
  assert_true(
    anthropic_v4_provider_tool_result(fetch, "web_fetch", warnings)
    is Some(
      {
        "type": "web_fetch_tool_result",
        "tool_use_id": "fetch-1",
        "content": {
          "type": "web_fetch_result",
          "retrieved_at": "2026-08-07T00:00:00Z",
          "content": {
            "citations": { "enabled": true, .. },
            "source": { "media_type": "text/plain", .. },
            ..
          },
          ..
        },
        ..
      }
    ),
  )
  let fetch_error = @provider.LanguageModelV4ToolResultPart::error_json(
    tool_call_id="fetch-error",
    tool_name="web_fetch",
    value={ "errorCode": "url_not_allowed" },
  )
  assert_true(
    anthropic_v4_provider_tool_result(fetch_error, "web_fetch", warnings)
    is Some(
      {
        "content": {
          "type": "web_fetch_tool_result_error",
          "error_code": "url_not_allowed",
          ..
        },
        ..
      }
    ),
  )
  let search = @provider.LanguageModelV4ToolResultPart::json(
    tool_call_id="search-1",
    tool_name="web_search",
    value=[
      {
        "type": "web_search_result",
        "url": "https://moonbitlang.com",
        "title": "MoonBit",
        "pageAge": null,
        "encryptedContent": "encrypted",
      },
    ],
  )
  assert_true(
    anthropic_v4_provider_tool_result(search, "web_search", warnings)
    is Some(
      {
        "content": [
          {
            "type": "web_search_result",
            "page_age": Null,
            "encrypted_content": "encrypted",
            ..
          },
        ],
        ..
      }
    ),
  )
  let search_error = @provider.LanguageModelV4ToolResultPart::error_json(
    tool_call_id="search-error",
    tool_name="web_search",
    value={ "error_code": "unavailable" },
  )
  assert_true(
    anthropic_v4_provider_tool_result(search_error, "web_search", warnings)
    is Some(
      {
        "content": {
          "type": "web_search_tool_result_error",
          "error_code": "unavailable",
          ..
        },
        ..
      }
    ),
  )
  let tool_search = @provider.LanguageModelV4ToolResultPart::json(
    tool_call_id="discover-1",
    tool_name="tool_search",
    value=[{ "type": "tool_reference", "toolName": "get_weather" }],
  )
  assert_true(
    anthropic_v4_provider_tool_result(
      tool_search, "tool_search_tool_bm25", warnings,
    )
    is Some(
      {
        "type": "tool_search_tool_result",
        "content": {
          "tool_references": [
            { "type": "tool_reference", "tool_name": "get_weather", .. },
          ],
          ..
        },
        ..
      }
    ),
  )
  let unsupported = @provider.LanguageModelV4ToolResultPart::error_text(
    tool_call_id="search-text-error",
    tool_name="web_search",
    value="failed",
  )
  assert_eq(
    anthropic_v4_provider_tool_result(unsupported, "web_search", warnings),
    None,
  )
  assert_eq(warnings.length(), 1)
}

///|
test "Anthropic decoder normalizes code tool-search and advisor results" {
  let response = decode_messages_response({
    "content": [
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "code-standard",
        "content": {
          "type": "code_execution_result",
          "stdout": "ok\n",
          "stderr": "",
          "return_code": 0,
        },
      },
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "code-encrypted",
        "content": {
          "type": "encrypted_code_execution_result",
          "encrypted_stdout": "ciphertext",
          "stderr": "",
          "return_code": 0,
        },
      },
      {
        "type": "code_execution_tool_result",
        "tool_use_id": "code-error",
        "content": {
          "type": "code_execution_tool_result_error",
          "error_code": "unavailable",
        },
      },
      {
        "type": "tool_search_tool_result",
        "tool_use_id": "search-success",
        "content": {
          "type": "tool_search_tool_search_result",
          "tool_references": [
            { "type": "tool_reference", "tool_name": "get_weather" },
          ],
        },
      },
      {
        "type": "tool_search_tool_result",
        "tool_use_id": "search-error",
        "content": {
          "type": "tool_search_tool_result_error",
          "error_code": "unavailable",
        },
      },
      {
        "type": "advisor_tool_result",
        "tool_use_id": "advisor-success",
        "content": { "type": "advisor_result", "text": "Use a queue." },
      },
      {
        "type": "advisor_tool_result",
        "tool_use_id": "advisor-redacted",
        "content": {
          "type": "advisor_redacted_result",
          "encrypted_content": "opaque",
        },
      },
      {
        "type": "advisor_tool_result",
        "tool_use_id": "advisor-error",
        "content": {
          "type": "advisor_tool_result_error",
          "error_code": "unavailable",
        },
      },
    ],
  })
  let results : Array[@provider.ToolResult] = []
  for part in response.content {
    match part {
      @provider.GeneratedToolResultOutput(result) => results.push(result)
      _ => ()
    }
  }
  assert_eq(results.length(), 8)
  assert_eq(results[0].result, {
    "type": "code_execution_result",
    "stdout": "ok\n",
    "stderr": "",
    "return_code": 0,
    "content": [],
  })
  assert_eq(results[1].result, {
    "type": "encrypted_code_execution_result",
    "encrypted_stdout": "ciphertext",
    "stderr": "",
    "return_code": 0,
    "content": [],
  })
  assert_true(results[2].is_error)
  assert_eq(results[2].result, {
    "type": "code_execution_tool_result_error",
    "errorCode": "unavailable",
  })
  assert_eq(results[3].result, [
    { "type": "tool_reference", "toolName": "get_weather" },
  ])
  assert_true(results[4].is_error)
  assert_eq(results[4].result, {
    "type": "tool_search_tool_result_error",
    "errorCode": "unavailable",
  })
  assert_eq(results[5].result, {
    "type": "advisor_result",
    "text": "Use a queue.",
  })
  assert_eq(results[6].result, {
    "type": "advisor_redacted_result",
    "encryptedContent": "opaque",
  })
  assert_true(results[7].is_error)
  assert_eq(results[7].result, {
    "type": "advisor_tool_result_error",
    "errorCode": "unavailable",
  })
}

///|
test "Anthropic V4 stream emits provider-executed tool results" {
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
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"code_execution_tool_result\",\"tool_use_id\":\"code-1\",\"content\":{\"type\":\"code_execution_result\",\"stdout\":\"ok\\n\",\"stderr\":\"\",\"return_code\":0}}}",
  )
  let batch = decoder.feed_line("")
  match batch.events[0] {
    @provider.V4ToolResultReady(result) => {
      assert_eq(result.tool_call_id, "code-1")
      assert_eq(result.tool_name, "code_execution")
      assert_false(result.is_error)
      assert_true(
        result.result
        is { "type": "code_execution_result", "stdout": "ok\n", .. },
      )
    }
    _ => fail("expected an Anthropic V4 provider-executed tool result")
  }
  let _ = decoder.feed_line(
    "data: {\"type\":\"content_block_stop\",\"index\":0}",
  )
  let stopped = decoder.feed_line("")
  assert_false(
    stopped.events.any(event => event is @provider.V4ToolResultReady(_)),
  )
}

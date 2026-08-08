///|
test "Anthropic prepares function and provider-defined tools" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("research and advise")],
      tools=[
        @provider.ToolDefinition::new(
          "lookup",
          { "type": "object" },
          description="Look up a record",
          input_examples=[{ "query": "MoonBit" }],
          strict=true,
          provider_options={
            "anthropic": {
              "cacheControl": { "type": "ephemeral", "ttl": "1h" },
              "eagerInputStreaming": true,
              "deferLoading": true,
              "allowedCallers": ["direct", "code_execution_20260120"],
            },
          },
        ),
        code_execution_20250825_tool(),
        computer_20251124_tool({
          "displayWidthPx": 1440,
          "displayHeightPx": 900,
          "displayNumber": 1,
          "enableZoom": true,
        }),
        web_fetch_20260209_tool(args={
          "maxUses": 3,
          "allowedDomains": ["moonbitlang.com"],
          "citations": { "enabled": true },
          "maxContentTokens": 4096,
        }),
        advisor_20260301_tool({
          "model": "claude-opus-4-8",
          "maxUses": 2,
          "caching": { "type": "ephemeral", "ttl": "5m" },
        }),
      ],
      tool_choice=@provider.Named("computer"),
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-sonnet-4-6",
    "messages": [
      {
        "role": "user",
        "content": [{ "type": "text", "text": "research and advise" }],
      },
    ],
    "max_tokens": 128000,
    "tools": [
      {
        "name": "lookup",
        "description": "Look up a record",
        "input_schema": { "type": "object" },
        "cache_control": { "type": "ephemeral", "ttl": "1h" },
        "defer_loading": true,
        "allowed_callers": ["direct", "code_execution_20260120"],
        "strict": true,
        "eager_input_streaming": true,
        "input_examples": [{ "query": "MoonBit" }],
      },
      { "type": "code_execution_20250825", "name": "code_execution" },
      {
        "type": "computer_20251124",
        "name": "computer",
        "display_width_px": 1440,
        "display_height_px": 900,
        "display_number": 1,
        "enable_zoom": true,
      },
      {
        "type": "web_fetch_20260209",
        "name": "web_fetch",
        "max_uses": 3,
        "allowed_domains": ["moonbitlang.com"],
        "citations": { "enabled": true },
        "max_content_tokens": 4096,
      },
      {
        "type": "advisor_20260301",
        "name": "advisor",
        "model": "claude-opus-4-8",
        "max_uses": 2,
        "caching": { "type": "ephemeral", "ttl": "5m" },
      },
    ],
    "tool_choice": { "type": "tool", "name": "computer" },
  })
  assert_eq(prepared.beta_features, [
    "structured-outputs-2025-11-13", "advanced-tool-use-2025-11-20", "code-execution-2025-08-25",
    "computer-use-2025-11-24", "code-execution-web-tools-2026-02-09", "advisor-tool-2026-03-01",
  ])
  assert_eq(prepared.warnings.length(), 0)
}

///|
test "Anthropic-compatible configs can disable native structured output and strict tools" {
  let prepared = prepare_anthropic_v4_request_with_config(
    "claude-sonnet-4-6",
    anthropic_test_v4_options_from_chat(
      @provider.ChatCallOptions::new(
        [@provider.LanguageModelMessage::user("return JSON")],
        tools=[
          @provider.ToolDefinition::new(
            "lookup",
            { "type": "object" },
            strict=true,
          ),
        ],
        response_format=@provider.ResponseFormat::json(schema={
          "type": "object",
          "properties": { "answer": { "type": "string" } },
        }),
      ),
    ),
    "compatible.messages",
    false,
    false,
    false,
  )
  guard prepared.body is { "tools": Array(tools), .. } else {
    fail("expected Anthropic tools")
  }
  assert_true(tools.any(tool => tool is { "name": "json", .. }))
  assert_false(tools[0].stringify().contains("\"strict\""))
  assert_false(prepared.body.stringify().contains("\"output_config\""))
  assert_false(prepared.beta_features.contains("structured-outputs-2025-11-13"))
  assert_true(
    prepared.warnings.any(warning => {
      warning is @provider.Warning::Unsupported(feature="strict", ..)
    }),
  )
}

///|
test "Anthropic function tool can disable model-level eager streaming" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      tools=[
        @provider.ToolDefinition::new(
          "lookup",
          { "type": "object" },
          description="Look up a record",
          provider_options={ "anthropic": { "eagerInputStreaming": false } },
        ),
      ],
    ),
    "anthropic.messages",
    true,
  )
  json_inspect(prepared.body, content={
    "model": "claude-sonnet-4-6",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 128000,
    "stream": true,
    "tools": [
      {
        "name": "lookup",
        "description": "Look up a record",
        "input_schema": { "type": "object" },
      },
    ],
  })
}

///|
test "Anthropic warns for unknown provider-defined tools" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      tools=[
        @provider.ToolDefinition::provider(id="other.unknown", name="unknown"),
      ],
    ),
    "anthropic.messages",
    false,
  )
  assert_eq(prepared.warnings.length(), 1)
  assert_true(
    prepared.warnings[0]
    is @provider.Unsupported(feature="provider-defined tool other.unknown", ..),
  )
}

///|
test "Anthropic maps custom provider-tool names across prompt and tool choice" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [
        @provider.LanguageModelMessage::assistant("", tool_calls=[
          @provider.ToolCall::new(
            id="server_1",
            name="research",
            arguments="{\"query\":\"MoonBit\"}",
            provider_executed=true,
          ),
        ]),
      ],
      tools=[web_search_20260209_tool(name="research")],
      tool_choice=@provider.Named("research"),
    ),
    "anthropic.messages",
    false,
  )
  match prepared.body {
    {
      "messages": [
        {
          "content": [
            { "type": "server_tool_use", "name": String(history_name), .. },
          ],
          ..
        },
      ],
      "tools": [
        { "type": "web_search_20260209", "name": String(tool_name), .. },
      ],
      "tool_choice": { "type": "tool", "name": String(choice_name), .. },
      ..
    } => {
      assert_eq(history_name, "web_search")
      assert_eq(tool_name, "web_search")
      assert_eq(choice_name, "web_search")
    }
    _ => fail("expected mapped Anthropic provider-tool names")
  }
}

///|
test "Anthropic maps custom provider-tool names in tool changes" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [
        @provider.LanguageModelMessage::user("first"),
        @provider.LanguageModelMessage::system("", provider_options={
          "anthropic": {
            "toolChanges": [{ "type": "tool_addition", "toolName": "research" }],
          },
        }),
      ],
      tools=[web_search_20260209_tool(name="research")],
    ),
    "anthropic.messages",
    false,
  )
  match prepared.body {
    {
      "messages": [
        _,
        {
          "role": "system",
          "content": [
            {
              "type": "tool_addition",
              "tool": { "type": "tool_reference", "name": String(name), .. },
              ..
            },
          ],
          ..
        },
      ],
      ..
    } => assert_eq(name, "web_search")
    _ => fail("expected mapped Anthropic tool change")
  }
}

///|
test "Anthropic strict-tool warning matches AI SDK" {
  let prepared = prepare_anthropic_request(
    "claude-3-haiku-20240307",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      tools=[
        @provider.ToolDefinition::new(
          "lookup",
          Json::empty_object(),
          strict=true,
        ),
      ],
    ),
    "anthropic.messages",
    false,
  )
  assert_true(
    prepared.warnings.any(fn(warning) {
      warning
      is @provider.Unsupported(
        feature="strict",
        details="Tool 'lookup' has strict: true, but strict mode is not supported by this provider. The strict property will be ignored."
      )
    }),
  )
}

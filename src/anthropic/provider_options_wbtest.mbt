///|
test "Anthropic reports protected options and maps standard reasoning" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    reasoning_effort=@provider.High,
    provider_options={ "anthropic": { "stream": false } },
  )
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6", options, "anthropic.messages", true,
  )
  let warnings = prepared.warnings
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0] is @provider.Compatibility(feature="providerOptions.stream", ..),
  )
  json_inspect(prepared.body, content={
    "model": "claude-sonnet-4-6",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 128000,
    "stream": true,
    "thinking": { "type": "adaptive", "display": "summarized" },
    "output_config": { "effort": "high" },
  })
}

///|
test "Anthropic configured headers override generated authentication" {
  let provider = create_anthropic(api_key="default-key", headers={
    "X-Api-Key": "override-key",
  })
  let model = provider.language_model_value("claude-test")
  let headers = model.request_headers(Map([]), request_beta_features=[])
  assert_eq(headers.get("x-api-key"), None)
  assert_eq(headers.get("X-Api-Key"), Some("override-key"))
}

///|
test "Anthropic merges beta headers into transforms and one request header" {
  let mut observed_betas : Array[String] = []
  let provider = create_anthropic(
    api_key="test-key",
    headers={ "Anthropic-Beta": "CONFIG-beta1, config-beta2" },
    transform_request_body=(body, betas) => {
      observed_betas = betas
      body
    },
  )
  let model = provider.language_model_value("claude-test")
  let request_headers = { "ANTHROPIC-BETA": "REQUEST-beta1, config-beta2" }
  let _ = model.apply_request_body_transform(
    Json::empty_object(),
    ["prepared-beta"],
    request_headers,
  )
  assert_eq(observed_betas, [
    "prepared-beta", "config-beta1", "config-beta2", "request-beta1",
  ])
  let headers = model.request_headers(request_headers, request_beta_features=[
    "prepared-beta",
  ])
  assert_eq(
    headers.get("anthropic-beta"),
    Some("prepared-beta,config-beta1,config-beta2,request-beta1"),
  )
  assert_eq(headers.get("Anthropic-Beta"), None)
  assert_eq(headers.get("ANTHROPIC-BETA"), None)
}

///|
test "Anthropic legacy models map standardized reasoning to a token budget" {
  let prepared = prepare_anthropic_request(
    "claude-3-haiku-20240307",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.Medium,
      temperature=0.5,
      top_p=0.7,
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-3-haiku-20240307",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 4096,
    "thinking": { "type": "enabled", "budget_tokens": 1229 },
  })
  assert_eq(prepared.warnings.length(), 2)
  assert_true(
    prepared.warnings[0] is @provider.Unsupported(feature="temperature", ..),
  )
  assert_true(prepared.warnings[1] is @provider.Unsupported(feature="topP", ..))
}

///|
test "Anthropic reasoning uses shared AI SDK effort mapping diagnostics" {
  let minimal = prepare_anthropic_request(
    "claude-opus-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.Minimal,
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(minimal.body, content={
    "model": "claude-opus-4-6",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 128000,
    "thinking": { "type": "adaptive", "display": "summarized" },
    "output_config": { "effort": "low" },
  })
  assert_true(
    minimal.warnings.any(fn(warning) {
      warning
      is @provider.Compatibility(
        feature="reasoning",
        details="reasoning \"minimal\" is not directly supported by this model. mapped to effort \"low\"."
      )
    }),
  )

  let xhigh = prepare_anthropic_request(
    "claude-opus-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.XHigh,
    ),
    "anthropic.messages",
    false,
  )
  assert_true(
    xhigh.warnings.any(fn(warning) {
      warning
      is @provider.Compatibility(
        feature="reasoning",
        details="reasoning \"xhigh\" is not directly supported by this model. mapped to effort \"max\"."
      )
    }),
  )
}

///|
test "Anthropic provider options contribute request beta features" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={
        "anthropic": {
          "anthropicBeta": ["custom-beta"],
          "mcpServers": [
            { "type": "url", "name": "docs", "url": "https://mcp.example.com" },
          ],
          "taskBudget": { "type": "tokens", "total": 20000 },
          "speed": "fast",
        },
      },
    ),
    "anthropic.messages",
    true,
  )
  assert_eq(prepared.beta_features, [
    "custom-beta", "mcp-client-2025-04-04", "task-budgets-2026-03-13", "fast-mode-2026-02-01",
  ])
}

///|
test "Anthropic custom namespace overrides canonical option defaults" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={
        "anthropic": {
          "effort": "low",
          "metadata": { "userId": "canonical-user" },
        },
        "localClaude": { "effort": "high" },
      },
    ),
    "local-claude.messages",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-sonnet-4-6",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 128000,
    "output_config": { "effort": "high" },
    "metadata": { "user_id": "canonical-user" },
  })
}

///|
test "Anthropic rejects a fractional thinking token budget" {
  let prepared = prepare_anthropic_request(
    "claude-3-haiku-20240307",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={
        "anthropic": {
          "thinking": { "type": "enabled", "budgetTokens": 2048.5 },
        },
      },
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-3-haiku-20240307",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 4096,
    "thinking": { "type": "enabled", "budget_tokens": 1024 },
  })
  assert_eq(prepared.warnings.length(), 2)
  assert_true(
    prepared.warnings[0]
    is @provider.Compatibility(
      feature="providerOptions.thinking.budgetTokens",
      ..
    ),
  )
  assert_true(
    prepared.warnings[1]
    is @provider.Compatibility(feature="extended thinking", ..),
  )
}

///|
test "Anthropic sends topK unless thinking disables sampling" {
  let regular = prepare_anthropic_request(
    "claude-3-haiku-20240307",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      top_k=40.0,
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(regular.body, content={
    "model": "claude-3-haiku-20240307",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 4096,
    "top_k": 40,
  })
  assert_eq(regular.warnings, [])

  let thinking = prepare_anthropic_request(
    "claude-3-haiku-20240307",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.Medium,
      top_k=40.0,
    ),
    "anthropic.messages",
    false,
  )
  assert_false(thinking.body.stringify().contains("top_k"))
  assert_eq(thinking.warnings.length(), 1)
  assert_true(thinking.warnings[0] is @provider.Unsupported(feature="topK", ..))
}

///|
test "Anthropic sanitizes nested provider options before wire encoding" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={
        "anthropic": {
          "cacheControl": { "type": "ephemeral", "ttl": "1h", "ignored": true },
          "mcpServers": [
            {
              "type": "url",
              "name": "docs",
              "url": "https://mcp.example.com",
              "authorizationToken": null,
              "toolConfiguration": {
                "enabled": true,
                "allowedTools": ["search"],
                "ignored": true,
              },
              "ignored": true,
            },
          ],
          "container": {
            "id": "container-1",
            "skills": [
              {
                "type": "anthropic",
                "skillId": "pptx",
                "version": "latest",
                "ignored": true,
              },
              {
                "type": "custom",
                "providerReference": { "anthropic": "skill-uploaded" },
                "ignored": true,
              },
            ],
            "ignored": true,
          },
          "taskBudget": {
            "type": "tokens",
            "total": 20000,
            "remaining": 10000,
            "ignored": true,
          },
          "fallbacks": [
            {
              "model": "claude-opus-4-8",
              "max_tokens": 8192,
              "thinking": { "type": "disabled" },
              "speed": "fast",
              "ignored": true,
            },
          ],
          "contextManagement": {
            "edits": [
              {
                "type": "compact_20260112",
                "trigger": { "type": "input_tokens", "value": 50000 },
                "pauseAfterCompaction": true,
                "instructions": "Keep the task state.",
                "ignored": true,
              },
            ],
            "ignored": true,
          },
        },
      },
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-sonnet-4-6",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 128000,
    "output_config": {
      "task_budget": { "type": "tokens", "total": 20000, "remaining": 10000 },
    },
    "cache_control": { "type": "ephemeral", "ttl": "1h" },
    "mcp_servers": [
      {
        "type": "url",
        "name": "docs",
        "url": "https://mcp.example.com",
        "tool_configuration": { "enabled": true, "allowed_tools": ["search"] },
      },
    ],
    "container": {
      "id": "container-1",
      "skills": [
        { "type": "anthropic", "skill_id": "pptx", "version": "latest" },
        { "type": "custom", "skill_id": "skill-uploaded" },
      ],
    },
    "fallbacks": [
      {
        "model": "claude-opus-4-8",
        "max_tokens": 8192,
        "thinking": { "type": "disabled" },
        "speed": "fast",
      },
    ],
    "context_management": {
      "edits": [
        {
          "type": "compact_20260112",
          "trigger": { "type": "input_tokens", "value": 50000 },
          "pause_after_compaction": true,
          "instructions": "Keep the task state.",
        },
      ],
    },
  })
  assert_eq(prepared.warnings, [
    @provider.Warning::Other(
      message="code execution tool is required when using skills",
    ),
  ])
}

///|
test "Anthropic ignores invalid nested provider options" {
  let prepared = prepare_anthropic_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={
        "anthropic": {
          "cacheControl": { "type": "persistent" },
          "mcpServers": [
            { "type": "url", "name": 42, "url": "https://mcp.example.com" },
          ],
          "container": { "skills": [{ "type": "anthropic", "skillId": 42 }] },
          "taskBudget": { "type": "tokens", "total": 19999 },
          "fallbacks": [{ "model": true }],
          "contextManagement": {
            "edits": [
              { "type": "compact_20260112", "pauseAfterCompaction": "yes" },
            ],
          },
        },
      },
    ),
    "anthropic.messages",
    false,
  )
  let body = prepared.body.stringify()
  assert_false(body.contains("cache_control"))
  assert_false(body.contains("mcp_servers"))
  assert_false(body.contains("container"))
  assert_false(body.contains("output_config"))
  assert_false(body.contains("fallbacks"))
  assert_false(body.contains("context_management"))
  assert_eq(prepared.beta_features, [])
  for
    feature in [
      "providerOptions.cacheControl.type", "providerOptions.mcpServers[0].name",
      "providerOptions.container.skills[0].skillId", "providerOptions.taskBudget.total",
      "providerOptions.fallbacks[0].model", "providerOptions.contextManagement.edits[0].pauseAfterCompaction",
    ] {
    assert_true(
      prepared.warnings.any(fn(warning) {
        warning is @provider.Compatibility(feature=actual, ..) &&
        actual == feature
      }),
    )
  }
}

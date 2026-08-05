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
  let model = provider.chat_wire("claude-test")
  let headers = model.request_headers(Map([]), request_beta_features=[])
  assert_eq(headers.get("x-api-key"), None)
  assert_eq(headers.get("X-Api-Key"), Some("override-key"))
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

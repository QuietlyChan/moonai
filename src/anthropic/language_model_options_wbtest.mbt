///|
test "typed custom Anthropic skills resolve provider references at request time" {
  let typed = AnthropicLanguageModelOptions::new(
    container=AnthropicContainer::new(id="container-1", skills=[
      AnthropicContainerSkill::custom(
        provider_reference=@provider.ProviderReference::single(
          provider="anthropic",
          id="skill-uploaded",
        ),
      ),
    ]),
  )
  let prepared = prepare_anthropic_request(
    "claude-opus-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options=typed.to_provider_options(),
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-opus-4-6",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "max_tokens": 128000,
    "container": {
      "id": "container-1",
      "skills": [{ "type": "custom", "skill_id": "skill-uploaded" }],
    },
  })
  assert_true(prepared.beta_features.contains("skills-2025-10-02"))
  assert_true(prepared.beta_features.contains("files-api-2025-04-14"))
  assert_true(
    prepared.warnings.any(fn(warning) {
      warning
      is @provider.Other(
        message="code execution tool is required when using skills"
      )
    }),
  )
}

///|
test "typed Anthropic context edits use API field names after wire conversion" {
  let typed = AnthropicLanguageModelOptions::new(
    context_management=AnthropicContextManagement::new(edits=[
      AnthropicContextManagementEdit::clear_thinking(
        keep=AnthropicThinkingKeep::turns(2.0),
      ),
      AnthropicContextManagementEdit::compact(
        trigger=AnthropicCompactionTrigger::new(value=9000.0),
        pause_after_compaction=true,
        instructions="keep the current task",
      ),
    ]),
  )
  let prepared = prepare_anthropic_request(
    "claude-opus-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options=typed.to_provider_options(),
    ),
    "anthropic.messages",
    false,
  )
  let text = prepared.body.stringify()
  assert_true(text.contains("clear_thinking_20251015"))
  assert_true(text.contains("thinking_turns"))
  assert_true(text.contains("compact_20260112"))
  assert_true(text.contains("pause_after_compaction"))
  assert_true(prepared.beta_features.contains("context-management-2025-06-27"))
  assert_true(prepared.beta_features.contains("compact-2026-01-12"))
}

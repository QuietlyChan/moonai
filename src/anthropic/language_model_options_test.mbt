///|
test "typed Anthropic language options encode the Messages wire contract" {
  let typed = AnthropicLanguageModelOptions::new(
    send_reasoning=false,
    structured_output_mode=AnthropicStructuredOutputFormat,
    thinking=AnthropicThinking::adaptive(display=AnthropicThinkingSummarized),
    disable_parallel_tool_use=true,
    cache_control=AnthropicCacheControl::new(ttl=AnthropicCacheOneHour),
    metadata=AnthropicMetadata::new(user_id="opaque-user"),
    mcp_servers=[
      AnthropicMcpServer::new(
        name="docs",
        url="https://mcp.example.com",
        authorization_token="token",
        tool_configuration=AnthropicMcpToolConfiguration::new(enabled=true, allowed_tools=[
          "search",
        ]),
      ),
    ],
    container=AnthropicContainer::new(skills=[
      AnthropicContainerSkill::built_in(
        skill_id="pdf-processing",
        version="latest",
      ),
    ]),
    tool_streaming=false,
    effort=AnthropicEffortHigh,
    task_budget=AnthropicTaskBudget::new(total=20000, remaining=12000),
    speed=AnthropicSpeedFast,
    inference_geo=AnthropicInferenceUs,
    fallbacks=AnthropicFallbacks::default_fallback(),
    anthropic_beta=["custom-beta"],
    context_management=AnthropicContextManagement::new(edits=[
      AnthropicContextManagementEdit::clear_tool_uses(
        trigger=AnthropicContextTrigger::input_tokens(5000.0),
        keep=AnthropicToolUseKeep::new(value=2.0),
        clear_at_least=AnthropicInputTokenClearAtLeast::new(value=1000.0),
        clear_tool_inputs=true,
        exclude_tools=["large_tool"],
      ),
    ]),
  )
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options=typed.to_provider_options(provider_name="anthropic"),
  )
  let body = encode_messages_request(
    "claude-opus-4-6",
    options,
    provider_name="anthropic.messages",
    stream=false,
  )
  let text = body.stringify()
  assert_true(
    text.contains(
      "\"thinking\":{\"type\":\"adaptive\",\"display\":\"summarized\"}",
    ),
  )
  assert_true(
    text.contains(
      "\"output_config\":{\"effort\":\"high\",\"task_budget\":{\"type\":\"tokens\",\"total\":20000,\"remaining\":12000}}",
    ),
  )
  assert_true(
    text.contains("\"cache_control\":{\"type\":\"ephemeral\",\"ttl\":\"1h\"}"),
  )
  assert_true(text.contains("\"metadata\":{\"user_id\":\"opaque-user\"}"))
  assert_true(text.contains("\"authorization_token\":\"token\""))
  assert_true(
    text.contains(
      "\"tool_configuration\":{\"enabled\":true,\"allowed_tools\":[\"search\"]}",
    ),
  )
  assert_true(
    text.contains(
      "\"container\":{\"skills\":[{\"type\":\"anthropic\",\"skill_id\":\"pdf-processing\",\"version\":\"latest\"}]}",
    ),
  )
  assert_true(text.contains("\"speed\":\"fast\""))
  assert_true(text.contains("\"inference_geo\":\"us\""))
  assert_true(text.contains("\"fallbacks\":\"default\""))
  assert_true(text.contains("\"context_management\":{\"edits\":[{"))
  assert_false(text.contains("sendReasoning"))
}

///|
test "typed Anthropic file and system options preserve provider namespaces" {
  let file_options = AnthropicFilePartProviderOptions::new(
    container_upload=true,
    citations=AnthropicCitations::new(enabled=true),
    title="guide.pdf",
    context="reference document",
  )
  let system_options = AnthropicSystemMessageProviderOptions::new(tool_changes=[
    AnthropicToolChange::addition("search"),
  ])
  let file_text = file_options
    .to_provider_options()
    .get("anthropic")
    .unwrap()
    .stringify()
  let system_text = system_options
    .to_provider_options()
    .get("anthropic")
    .unwrap()
    .stringify()
  assert_true(file_text.contains("\"containerUpload\":true"))
  assert_true(file_text.contains("\"citations\":{\"enabled\":true}"))
  assert_true(file_text.contains("\"title\":\"guide.pdf\""))
  assert_true(
    system_text.contains(
      "\"toolChanges\":[{\"type\":\"tool_addition\",\"toolName\":\"search\"}]",
    ),
  )
}

///|
test "typed Anthropic options validate task budget limits" {
  try AnthropicTaskBudget::new(total=19999) catch {
    Failure::Failure(message) => assert_true(message.contains("at least 20000"))
    error => fail("unexpected task budget error: \{error}")
  } noraise {
    _ => fail("expected a task budget validation error")
  }
}

///|
test "Anthropic fallback entries preserve nested API fields" {
  let fallback = AnthropicFallback::new(
    model="claude-sonnet-4-6",
    max_tokens=4096,
    thinking={
      "type": Json::string("enabled"),
      "budget_tokens": Json::number(1024.0),
    },
    output_config={ "json_schema": { "type": Json::string("object") } },
    speed=AnthropicSpeedStandard,
  )
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options=AnthropicLanguageModelOptions::new(
      fallbacks=AnthropicFallbacks::chain([fallback]),
    ).to_provider_options(),
  )
  let body = encode_messages_request(
    "claude-opus-4-6",
    options,
    provider_name="anthropic.messages",
    stream=false,
  )
  let text = body.stringify()
  assert_true(text.contains("\"max_tokens\":4096"))
  assert_true(text.contains("\"budget_tokens\":1024"))
  assert_true(text.contains("\"json_schema\":{\"type\":\"object\"}"))
  assert_true(text.contains("\"speed\":\"standard\""))
}

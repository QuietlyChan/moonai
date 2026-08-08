///|
test "typed OpenAI Responses options encode through the provider namespace" {
  let tool = @provider.LanguageModelV4Tool::function("weather", {
    "type": "object",
    "properties": Json::empty_object(),
  })
  let typed = OpenAILanguageModelResponsesOptions::new(
    include_values=[OpenAIIncludeMessageOutputTextLogprobs],
    logprobs=OpenAILogprobs::top(4),
    max_tool_calls=2,
    parallel_tool_calls=false,
    prompt_cache_options=OpenAIPromptCacheOptions::new(
      mode=OpenAIPromptCacheExplicit,
      ttl=OpenAIPromptCacheThirtyMinutes,
    ),
    reasoning_effort="none",
    reasoning_mode=OpenAIReasoningPro,
    reasoning_context=OpenAIReasoningContextAllTurns,
    service_tier=OpenAIServiceTierFlex,
    store=false,
    text_verbosity=OpenAITextVerbosityHigh,
    truncation=OpenAITruncationDisabled,
    system_message_mode=OpenAISystemMessageDeveloper,
    context_management=[
      OpenAIContextManagement::compaction(compact_threshold=0.8),
    ],
    allowed_tools=OpenAIAllowedTools::new(
      tool_names=["weather"],
      mode=OpenAIAllowedToolsRequired,
    ),
  )
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    tools=[tool],
    provider_options=typed.to_provider_options(),
  )
  let body = prepare_openai_v4_responses_request(
      "gpt-5.6", options, "openai.responses", false,
    ).body
  let text = body.stringify()
  assert_true(
    text.contains(
      "\"include\":[\"message.output_text.logprobs\",\"reasoning.encrypted_content\"]",
    ),
  )
  assert_true(text.contains("\"top_logprobs\":4"))
  assert_true(
    text.contains(
      "\"prompt_cache_options\":{\"mode\":\"explicit\",\"ttl\":\"30m\"}",
    ),
  )
  assert_true(
    text.contains(
      "\"reasoning\":{\"effort\":\"none\",\"mode\":\"pro\",\"context\":\"all_turns\"}",
    ),
  )
  assert_true(
    text.contains(
      "\"context_management\":[{\"type\":\"compaction\",\"compact_threshold\":0.8}]",
    ),
  )
  assert_true(
    text.contains(
      "\"tool_choice\":{\"type\":\"allowed_tools\",\"mode\":\"required\"",
    ),
  )
  assert_false(text.contains("include_values"))
}

///|
test "typed OpenAI Chat options encode provider-specific fields" {
  let typed = OpenAILanguageModelChatOptions::new(
    logit_bias={ "42": -2.0 },
    logprobs=OpenAILogprobs::enabled(),
    parallel_tool_calls=false,
    user="typed-user",
    max_completion_tokens=128,
    store=true,
    metadata={ "tenant": "moonai" },
    prediction={ "type": "content", "content": "cached" },
    service_tier=OpenAIServiceTierPriority,
    strict_json_schema=false,
    text_verbosity=OpenAITextVerbosityLow,
    prompt_cache_key="prefix-1",
    prompt_cache_options=OpenAIPromptCacheOptions::new(
      mode=OpenAIPromptCacheImplicit,
    ),
    prompt_cache_retention=OpenAIPromptCacheTwentyFourHours,
    safety_identifier="user-1",
    system_message_mode=OpenAISystemMessageSystem,
  )
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4SystemMessage(
        content="You are helpful.",
        provider_options=Map([]),
      ),
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    provider_options=typed.to_provider_options(provider_name="openai"),
  )
  let body = prepare_openai_v4_chat_request(
      "gpt-4o", options, "openai.chat", false, true,
    ).body
  let text = body.stringify()
  assert_true(text.contains("\"logit_bias\":{\"42\":-2"))
  assert_true(text.contains("\"logprobs\":true"))
  assert_true(text.contains("\"top_logprobs\":0"))
  assert_true(text.contains("\"max_completion_tokens\":128"))
  assert_true(text.contains("\"metadata\":{\"tenant\":\"moonai\"}"))
  assert_true(
    text.contains(
      "\"prediction\":{\"type\":\"content\",\"content\":\"cached\"}",
    ),
  )
  assert_true(text.contains("\"service_tier\":\"priority\""))
  assert_true(text.contains("\"verbosity\":\"low\""))
  assert_true(text.contains("\"prompt_cache_key\":\"prefix-1\""))
  assert_true(text.contains("\"prompt_cache_retention\":\"24h\""))
  assert_true(text.contains("\"safety_identifier\":\"user-1\""))
}

///|
test "typed OpenAI options validate protocol limits" {
  try
    OpenAILanguageModelResponsesOptions::new(logprobs=OpenAILogprobs::top(21))
  catch {
    Failure::Failure(message) =>
      assert_true(message.contains("between 1 and 20"))
    error => fail("unexpected OpenAI options error: \{error}")
  } noraise {
    _ => fail("expected invalid Responses logprobs to be rejected")
  }
  try OpenAIAllowedTools::new(tool_names=[]) catch {
    Failure::Failure(message) =>
      assert_true(message.contains("at least one tool name"))
    error => fail("unexpected allowed-tools error: \{error}")
  } noraise {
    _ => fail("expected empty allowed-tools list to be rejected")
  }
}

///|
test "Moonshot AI options transform thinking and reasoning history" {
  let options = MoonshotAILanguageModelOptions::new(
    reasoning_effort="max",
    thinking_type="enabled",
    thinking_budget_tokens=2048,
    reasoning_history="interleaved",
  )
  json_inspect(options.to_provider_options(), content={
    "moonshotai": {
      "reasoningEffort": "max",
      "thinking": { "type": "enabled", "budgetTokens": 2048 },
      "reasoningHistory": "interleaved",
    },
  })
  json_inspect(
    moonshotai_transform_request_body({
      "model": "kimi-k2-thinking",
      "thinking": { "type": "enabled", "budgetTokens": 2048 },
      "reasoningHistory": "interleaved",
    }),
    content={
      "model": "kimi-k2-thinking",
      "thinking": { "type": "enabled", "budget_tokens": 2048 },
      "reasoning_history": "interleaved",
    },
  )
}

///|
test "Moonshot AI strips top-level JSON Schema keyword" {
  let transformed = moonshotai_transform_request_body({
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "answer",
        "schema": {
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "type": "object",
        },
      },
    },
  })
  assert_true(!transformed.stringify().contains("$schema"))
  assert_true(transformed.stringify().contains("\"type\":\"object\""))
}

///|
test "Moonshot AI usage prefers native cache accounting" {
  let usage = convert_moonshotai_chat_usage(
    Some({
      "prompt_tokens": 100,
      "completion_tokens": 80,
      "cached_tokens": 35,
      "prompt_tokens_details": { "cached_tokens": 20 },
      "completion_tokens_details": { "reasoning_tokens": 30 },
    }),
  )
  assert_eq(usage.input_tokens.total, Some(100))
  assert_eq(usage.input_tokens.no_cache, Some(65))
  assert_eq(usage.input_tokens.cache_read, Some(35))
  assert_eq(usage.output_tokens.text, Some(50))
  assert_eq(usage.output_tokens.reasoning, Some(30))
}

///|
test "Moonshot AI model capabilities and public selectors" {
  assert_true(get_model_structured_output_support("kimi-k2.5"))
  assert_true(!get_model_structured_output_support("moonshot-v1-8k"))
  let provider = createMoonshotAI(api_key="test-key")
  let generic = provider as &@provider.ProviderV4
  assert_eq(generic.specification_version(), "v4")
  let model = provider.chatModel("kimi-k3")
  assert_eq(model.provider(), "moonshotai.chat")
  assert_eq(model.model_id(), "kimi-k3")
}

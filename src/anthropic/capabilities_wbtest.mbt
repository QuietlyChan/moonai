///|
test "Anthropic legacy model matching follows AI SDK boundaries" {
  let model_ids = [
    "claude-instant", "anthropic.claude-instant-v1", "claude-2", "anthropic.claude-2:1",
    "claude-v2.1", "anthropic.claude-v2-legacy", "claude-3", "anthropic.claude-3.5-sonnet",
    "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
  ]
  for model_id in model_ids {
    let capabilities = get_anthropic_model_capabilities(model_id)
    assert_eq(capabilities.max_output_tokens, 4096)
    assert_eq(capabilities.supports_structured_output, false)
    assert_eq(capabilities.supports_adaptive_thinking, false)
    assert_eq(capabilities.rejects_sampling_parameters, false)
    assert_eq(capabilities.is_known_model, false)
  }
}

///|
test "Anthropic future model prefixes do not match legacy families" {
  let model_ids = [
    "claude-instantaneous", "anthropic.claude-20-sonnet", "anthropic.claude-v20:1",
    "claude-30-sonnet", "anthropic.claude-3:future",
  ]
  for model_id in model_ids {
    let capabilities = get_anthropic_model_capabilities(model_id)
    assert_eq(capabilities.max_output_tokens, 128000)
    assert_eq(capabilities.supports_structured_output, true)
    assert_eq(capabilities.supports_adaptive_thinking, true)
    assert_eq(capabilities.rejects_sampling_parameters, true)
    assert_eq(capabilities.is_known_model, false)
  }
}

///|
test "Anthropic future models reject sampling before thinking diagnostics" {
  let prepared = prepare_anthropic_v4_request(
    "claude-future-9",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([]),
      max_output_tokens=1024,
      temperature=0.7,
      top_k=40.0,
      top_p=0.8,
      provider_options=AnthropicLanguageModelOptions::new(
        thinking=AnthropicThinking::adaptive(
          display=AnthropicThinkingSummarized,
        ),
      ).to_provider_options(),
    ),
    "anthropic.messages",
    false,
  )
  assert_true(
    prepared.body
    is { "thinking": { "type": "adaptive", "display": "summarized", .. }, .. },
  )
  let body = prepared.body.stringify()
  assert_false(body.contains("temperature"))
  assert_false(body.contains("top_k"))
  assert_false(body.contains("top_p"))
  assert_eq(prepared.warnings, [
    @provider.Warning::Unsupported(
      feature="temperature",
      details="temperature is not supported by claude-future-9 and will be ignored",
    ),
    @provider.Warning::Unsupported(
      feature="topK",
      details="topK is not supported by claude-future-9 and will be ignored",
    ),
    @provider.Warning::Unsupported(
      feature="topP",
      details="topP is not supported by claude-future-9 and will be ignored",
    ),
  ])
}

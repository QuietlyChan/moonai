///|
test "OpenAI capability resolver identifies reasoning model families" {
  let o1 = get_openai_language_model_capabilities("o1")
  assert_eq(o1.is_reasoning_model, true)
  assert_eq(o1.system_message_mode, "developer")
  assert_eq(o1.supports_flex_processing, false)
  assert_eq(o1.supports_priority_processing, false)
  let o3 = get_openai_language_model_capabilities("o3-mini")
  assert_eq(o3.supports_flex_processing, true)
  assert_eq(o3.supports_priority_processing, true)
  let gpt51 = get_openai_language_model_capabilities("gpt-5.1")
  assert_eq(gpt51.is_reasoning_model, true)
  assert_eq(gpt51.supports_non_reasoning_parameters, true)
}

///|
test "OpenAI capability resolver keeps chat and custom IDs conservative" {
  let chat = get_openai_language_model_capabilities("gpt-5-chat-latest")
  assert_eq(chat.is_reasoning_model, false)
  assert_eq(chat.supports_flex_processing, false)
  let nano = get_openai_language_model_capabilities("gpt-5-nano")
  assert_eq(nano.supports_priority_processing, false)
  let custom = get_openai_language_model_capabilities("custom-gpt-5")
  assert_eq(custom.is_reasoning_model, false)
  assert_eq(custom.system_message_mode, "system")
  for malformed in ["gpt-5.1.2", "gpt-5.", "gpt-5-"] {
    let capabilities = get_openai_language_model_capabilities(malformed)
    assert_false(capabilities.is_reasoning_model)
    assert_eq(capabilities.system_message_mode, "system")
    assert_false(capabilities.supports_flex_processing)
    assert_false(capabilities.supports_priority_processing)
  }
}

///|
test "OpenAI future model IDs use reasoning-safe request defaults" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(
      content="Follow the instructions.",
      provider_options=Map([]),
    ),
    @provider.V4UserMessage(
      content=[@provider.V4PromptText(text="Say ok.", provider_options=Map([]))],
      provider_options=Map([]),
    ),
  ])
  let options = @provider.LanguageModelV4CallOptions::new(
    prompt,
    max_output_tokens=64,
    temperature=0.2,
    top_p=0.8,
    frequency_penalty=0.1,
    presence_penalty=0.1,
    provider_options={ "openai": { "logitBias": { "1": 1 }, "logprobs": 2 } },
  )
  let chat_body = prepare_openai_v4_chat_request(
      "gpt-99", options, "openai.chat", false, true,
    ).body
  assert_true(
    chat_body
    is {
      "messages": [{ "role": "developer", .. }, ..],
      "max_completion_tokens": Number(value, ..),
      ..
    } &&
    value == 64.0,
  )
  guard chat_body is Object(chat_fields) else {
    fail("expected an OpenAI Chat request object")
  }
  for
    omitted in [
      "max_tokens", "temperature", "top_p", "frequency_penalty", "presence_penalty",
      "logit_bias", "logprobs", "top_logprobs",
    ] {
    assert_true(chat_fields.get(omitted) is None)
  }
  let responses_body = prepare_openai_v4_responses_request(
      "gpt-99",
      @provider.LanguageModelV4CallOptions::new(
        prompt,
        temperature=0.2,
        top_p=0.8,
        provider_options={ "openai": { "reasoningEffort": "medium" } },
      ),
      "openai.responses",
      false,
    ).body
  assert_true(
    responses_body is { "input": [{ "role": "developer", .. }, ..], .. },
  )
  guard responses_body is Object(response_fields) else {
    fail("expected an OpenAI Responses request object")
  }
  assert_true(response_fields.get("temperature") is None)
  assert_true(response_fields.get("top_p") is None)
}

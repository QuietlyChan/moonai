///|
test "DeepSeek message level name and assistant prefix are forwarded" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(content="You are helpful.", provider_options={
      "deepseek": { "name": "helper-bot" },
    }),
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(text="continue this", provider_options=Map([])),
      ],
      provider_options=Map([]),
    ),
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptText(
          text="Sure, the answer is",
          provider_options=Map([]),
        ),
      ],
      provider_options={ "deepseek": { "prefix": true } },
    ),
  ])
  let prepared = prepare_deepseek_v4_request(
    "deepseek-chat",
    @provider.LanguageModelV4CallOptions::new(prompt),
    "deepseek.chat",
    false,
    true,
    false,
    true,
  ) catch {
    _ => fail("unexpected error")
  }
  let body = prepared.body.stringify()
  assert_true(body.contains("\"name\":\"helper-bot\""))
  assert_true(body.contains("\"prefix\":true"))
}

///|
test "completion prompt conversion matches the AI SDK transcript shape" {
  let converted = @provider_utils.convert_to_completion_prompt(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4SystemMessage(content="be concise", provider_options=Map([])),
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
      @provider.V4AssistantMessage(
        content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
  )
  assert_eq(converted, @provider_utils.CompletionPrompt::{
    prompt: "be concise\n\nuser:\nhello\n\nassistant:\nhi\n\nassistant:\n",
    stop_sequences: ["\nuser:"],
  })
}

///|
test "completion prompt rejects tool messages" {
  try
    @provider_utils.convert_to_completion_prompt(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4ToolMessage(content=[], provider_options=Map([])),
      ]),
    )
  catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_eq(functionality, "tool messages")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected tool message rejection")
  }
}

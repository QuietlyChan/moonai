///|
test "chat call options preserve an unspecified tool choice" {
  let default_options = ChatCallOptions::new([
    LanguageModelMessage::user("hello"),
  ])
  assert_eq(default_options.tool_choice, None)

  let explicit_options = ChatCallOptions::new(
    [LanguageModelMessage::user("hello")],
    tool_choice=Auto,
  )
  assert_eq(explicit_options.tool_choice, Some(Auto))
}

///|
test "messages and content parts retain provider-specific options" {
  let part = LanguageModelContentPart::text("cached").with_provider_options({
    "anthropic": { "cacheControl": { "type": "ephemeral" } },
  })
  let message = LanguageModelMessage::user_parts([part], provider_options={
    "anthropic": { "cacheControl": { "type": "ephemeral" } },
  })
  assert_true(message.parts[0].provider_options().get("anthropic") is Some(_))
  assert_eq(message.provider_options.get("anthropic") is Some(_), true)

  let merged = message.with_provider_options({
    "anthropic": { "metadata": { "request_id": "test" } },
  })
  assert_true(merged.provider_options.get("anthropic") is Some(_))
}

///|
test "assistant tool calls are normalized from content parts without duplicates" {
  let call = ToolCall::new(id="call-1", name="lookup", arguments="{}")
  let message = LanguageModelMessage::assistant_parts(
    [LanguageModelContentPart::tool_call(call)],
    tool_calls=[call],
  )
  let calls = message.effective_tool_calls()
  assert_eq(calls.length(), 1)
  assert_eq(calls[0], call)
}

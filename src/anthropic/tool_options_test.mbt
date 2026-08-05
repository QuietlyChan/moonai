///|
test "typed Anthropic tool options encode canonical provider fields" {
  let options = AnthropicToolOptions::new(
    defer_loading=true,
    allowed_callers=[AnthropicToolDirect, AnthropicToolCodeExecution20260120],
    eager_input_streaming=false,
  )
  let provider_options = options.to_provider_options()
  match provider_options.get("anthropic") {
    Some(value) => {
      let text = value.stringify()
      assert_true(text.contains("\"deferLoading\":true"))
      assert_true(
        text.contains(
          "\"allowedCallers\":[\"direct\",\"code_execution_20260120\"]",
        ),
      )
      assert_true(text.contains("\"eagerInputStreaming\":false"))
    }
    None => fail("expected anthropic provider namespace")
  }
}

///|
test "typed Anthropic tool options reach function tool wire encoding" {
  let tool = @provider.ToolDefinition::new(
    "search",
    { "type": "object", "properties": Json::empty_object() },
    provider_options=AnthropicToolOptions::new(
      defer_loading=true,
      allowed_callers=[AnthropicToolDirect],
      eager_input_streaming=true,
    ).to_provider_options(),
  )
  let body = encode_messages_request(
    "claude-sonnet-4-6",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      tools=[tool],
    ),
    provider_name="anthropic.messages",
    stream=false,
  )
  let text = body.stringify()
  assert_true(text.contains("\"defer_loading\":true"))
  assert_true(text.contains("\"allowed_callers\":[\"direct\"]"))
  assert_true(text.contains("\"eager_input_streaming\":true"))
}

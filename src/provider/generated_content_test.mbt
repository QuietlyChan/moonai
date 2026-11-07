///|
test "ordered generated content preserves provider output and aggregates helpers" {
  let call = @provider.ToolCall::new(
    id="call_1",
    name="lookup",
    arguments="{\"id\":1}",
    provider_executed=true,
  )
  let content : Array[@provider.GeneratedContent] = [
    @provider.GeneratedContent::reasoning("check the index"),
    @provider.GeneratedContent::text("found it"),
    @provider.GeneratedContent::url_source(
      id="source_1",
      url="https://example.com",
      title="Example",
    ),
    @provider.GeneratedContent::tool_call(call),
  ]
  let response = @provider.ChatResponse::from_content(
    content,
    @provider.Usage::zero(),
    ToolCalls,
  )
  assert_eq(response.text, "found it")
  assert_eq(response.reasoning, "check the index")
  assert_eq(response.tool_calls, [call])
  assert_eq(response.content, content)
}

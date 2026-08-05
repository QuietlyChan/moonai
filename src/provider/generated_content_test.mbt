///|
test "ordered generated content preserves provider output and aggregates helpers" {
  let call = ToolCall::new(
    id="call_1",
    name="lookup",
    arguments="{\"id\":1}",
    provider_executed=true,
  )
  let content : Array[GeneratedContent] = [
    GeneratedContent::reasoning("check the index"),
    GeneratedContent::text("found it"),
    GeneratedContent::url_source(
      id="source_1",
      url="https://example.com",
      title="Example",
    ),
    GeneratedContent::tool_call(call),
  ]
  let response = ChatResponse::from_content(content, Usage::zero(), ToolCalls)
  assert_eq(response.text, "found it")
  assert_eq(response.reasoning, "check the index")
  assert_eq(response.tool_calls, [call])
  assert_eq(response.content, content)
}

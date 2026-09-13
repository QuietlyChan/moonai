///|
test "workflow session snapshot roundtrips full history" {
  let messages = [
    @provider_utils.ModelMessage::user("what is Moon?"),
    @provider_utils.ModelMessage::assistant(
      "checking",
      tool_calls=[
        @provider_utils.ModelToolCall::new(id="call-1", name="lookup", input={
          "query": "Moon",
        }),
      ],
      reasoning_content="thinking",
    ),
    @provider_utils.ModelMessage::tool("call-1", "a moon"),
    @provider_utils.ModelMessage::assistant("Moon it is"),
  ]
  let snapshot : WorkflowSessionSnapshot = {
    agent_id: Some("research-agent"),
    messages,
    steps: 2,
  }
  let restored = workflow_snapshot_from_json(
    value=workflow_snapshot_to_json(snapshot~),
  )
  assert_eq(restored.agent_id, Some("research-agent"))
  assert_eq(restored.steps, 2)
  assert_eq(restored.messages.length(), 4)
  assert_eq(restored.messages[0].role, @provider_utils.ModelUser)
  assert_eq(restored.messages[0].content, "what is Moon?")
  assert_eq(restored.messages[1].tool_calls[0].name, "lookup")
  assert_eq(restored.messages[1].reasoning_content, Some("thinking"))
  assert_eq(restored.messages[2].role, @provider_utils.ModelTool("call-1"))
  assert_eq(restored.messages[3].content, "Moon it is")
}

///|
test "workflow snapshot rejects unknown roles and missing ids" {
  try
    workflow_snapshot_from_json(value={ "messages": [{ "role": "referee" }] })
  catch {
    WorkflowError(message~) =>
      assert_true(message.contains("unknown snapshot role"))
    error => fail("unexpected error \{@debug.to_string(error)}")
  } noraise {
    _ => fail("expected snapshot rejection")
  }
  try
    workflow_snapshot_from_json(value={
      "messages": [{ "role": "tool", "content": "x" }],
    })
  catch {
    WorkflowError(message~) => assert_true(message.contains("tool_call_id"))
    error => fail("unexpected error \{@debug.to_string(error)}")
  } noraise {
    _ => fail("expected snapshot rejection")
  }
}

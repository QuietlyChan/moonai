///|
test "tool call delta assembler handles interleaved calls" {
  let assembler = ToolCallDeltaAssembler::new()
  let first = assembler.apply(
    ToolCallDelta::new(
      index=0,
      id="call_weather",
      name="get_weather",
      arguments_delta="{\"city\"",
    ),
  )
  let second = assembler.apply(
    ToolCallDelta::new(
      index=1,
      id="call_time",
      name="get_time",
      arguments_delta="{\"zone\"",
    ),
  )
  let _ = assembler.apply(
    ToolCallDelta::new(index=0, arguments_delta=":\"Hangzhou\"}"),
  )
  let _ = assembler.apply(
    ToolCallDelta::new(index=1, arguments_delta=":\"Asia/Shanghai\"}"),
  )
  assert_true(first.started)
  assert_true(second.started)
  assert_eq(assembler.calls(), [
    ToolCall::new(
      id="call_weather",
      name="get_weather",
      arguments="{\"city\":\"Hangzhou\"}",
    ),
    ToolCall::new(
      id="call_time",
      name="get_time",
      arguments="{\"zone\":\"Asia/Shanghai\"}",
    ),
  ])
}

///|
test "tool call delta assembler keeps a stable synthetic stream id" {
  let assembler = ToolCallDeltaAssembler::new()
  let first = assembler.apply(ToolCallDelta::new(index=0, arguments_delta="{"))
  let second = assembler.apply(
    ToolCallDelta::new(
      index=0,
      id="late-id",
      name="late_tool",
      arguments_delta="}",
    ),
  )
  assert_eq(first.stream_id, "tool-0")
  assert_eq(second.stream_id, "tool-0")
  assert_eq(assembler.calls(), [
    ToolCall::new(id="late-id", name="late_tool", arguments="{}"),
  ])
}

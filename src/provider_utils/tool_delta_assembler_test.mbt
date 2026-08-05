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
    @provider.ToolCall::new(
      id="call_weather",
      name="get_weather",
      arguments="{\"city\":\"Hangzhou\"}",
    ),
    @provider.ToolCall::new(
      id="call_time",
      name="get_time",
      arguments="{\"zone\":\"Asia/Shanghai\"}",
    ),
  ])
}

///|
test "tool call delta assembler keeps a stable synthetic stream id" {
  let assembler = ToolCallDeltaAssembler::new(id_generator=() => "tool-0")
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
    @provider.ToolCall::new(id="late-id", name="late_tool", arguments="{}"),
  ])
}

///|
test "tool call delta assembler merges provider metadata" {
  let assembler = ToolCallDeltaAssembler::new()
  let _ = assembler.apply(
    ToolCallDelta::new(index=0, id="call-1", name="lookup", provider_metadata={
      "google": { "thoughtSignature": "sig-1" },
    }),
  )
  let _ = assembler.apply(
    ToolCallDelta::new(index=0, arguments_delta="{}", provider_metadata={
      "google": { "traceId": "trace-1" },
    }),
  )
  assert_eq(assembler.calls(), [
    @provider.ToolCall::new(id="call-1", name="lookup", arguments="{}", provider_metadata={
      "google": { "thoughtSignature": "sig-1", "traceId": "trace-1" },
    }),
  ])
}

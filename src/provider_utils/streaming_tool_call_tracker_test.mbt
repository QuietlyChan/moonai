///|
test "streaming tool call tracker accumulates interleaved calls until flush" {
  let tracker = StreamingToolCallTracker::new()
  let first = tracker.process_delta(
    StreamingToolCallDelta::new(
      index=0,
      id="call_weather",
      tool_type="function",
      function_name="get_weather",
      arguments_delta="{\"city\"",
    ),
  )
  let second = tracker.process_delta(
    StreamingToolCallDelta::new(
      index=1,
      id="call_time",
      tool_type="function",
      function_name="get_time",
      arguments_delta="{\"zone\"",
    ),
  )
  let first_tail = tracker.process_delta(
    StreamingToolCallDelta::new(index=0, arguments_delta=":\"Hangzhou\"}"),
  )
  let _ = tracker.process_delta(
    StreamingToolCallDelta::new(index=1, arguments_delta=":\"Asia/Shanghai\"}"),
  )
  assert_true(
    first[0]
    is @provider.ToolInputStart(id="call_weather", tool_name="get_weather"),
  )
  assert_true(
    second[0] is @provider.ToolInputStart(id="call_time", tool_name="get_time"),
  )
  assert_true(
    first_tail[0]
    is @provider.ToolInputDelta(id="call_weather", delta=":\"Hangzhou\"}"),
  )
  let terminal = tracker.flush()
  assert_eq(terminal.length(), 4)
  assert_true(terminal[0] is @provider.ToolInputEnd("call_weather"))
  assert_true(
    terminal[1]
    is @provider.ToolCallReady(
      {
        id: "call_weather",
        name: "get_weather",
        arguments: "{\"city\":\"Hangzhou\"}",
        ..,
      }
    ),
  )
  assert_eq(tracker.calls(), [
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
test "streaming tool call tracker emits V4 lifecycle parts directly" {
  let tracker = StreamingToolCallTracker::new()
  let first = tracker.process_delta_v4(
    StreamingToolCallDelta::new(
      index=0,
      id="call-1",
      function_name="lookup",
      arguments_delta="{\"city\"",
    ),
  )
  let tail = tracker.process_delta_v4(
    StreamingToolCallDelta::new(index=0, arguments_delta=":\"Hangzhou\"}"),
  )
  assert_true(
    first[0]
    is @provider.V4ToolInputStart(
      id="call-1",
      tool_name="lookup",
      provider_executed=false,
      dynamic=false,
      ..
    ),
  )
  assert_true(
    tail[0]
    is @provider.V4ToolInputDelta(id="call-1", delta=":\"Hangzhou\"}", ..),
  )
  let terminal = tracker.flush_v4()
  assert_true(terminal[0] is @provider.V4ToolInputEnd(id="call-1", ..))
  assert_true(
    terminal[1]
    is @provider.V4ToolCallReady(
      {
        tool_call_id: "call-1",
        tool_name: "lookup",
        input: "{\"city\":\"Hangzhou\"}",
        ..,
      }
    ),
  )
}

///|
test "streaming tool call tracker never finalizes parsable arguments early" {
  let tracker = StreamingToolCallTracker::new()
  let events = tracker.process_delta(
    StreamingToolCallDelta::new(
      index=0,
      id="call-1",
      function_name="search",
      arguments_delta="{\"query\":\"MoonBit\"}",
    ),
  )
  assert_eq(events.length(), 2)
  assert_false(events.any(event => event is @provider.ToolInputEnd(_)))
  assert_false(events.any(event => event is @provider.ToolCallReady(_)))
  assert_eq(tracker.flush().length(), 2)
}

///|
test "streaming tool call tracker validates required first-delta fields" {
  let missing_id = StreamingToolCallTracker::new()
  try
    missing_id.process_delta(
      StreamingToolCallDelta::new(index=0, function_name="lookup", data={
        "index": 0,
        "function": { "name": "lookup" },
      }),
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_eq(message, "Expected 'id' to be a string.")
      assert_true(data is { "index": 0, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed missing-id error")
  }
  let missing_name = StreamingToolCallTracker::new()
  try
    missing_name.process_delta(
      StreamingToolCallDelta::new(index=0, id="call-1"),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_eq(message, "Expected 'function.name' to be a string.")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed missing-name error")
  }
}

///|
test "streaming tool call tracker supports AI SDK type validation modes" {
  let none = StreamingToolCallTracker::new()
  let _ = none.process_delta(
    StreamingToolCallDelta::new(
      index=0,
      id="call-none",
      tool_type="custom",
      function_name="lookup",
    ),
  )
  let if_present = StreamingToolCallTracker::new(
    type_validation=ValidateToolCallTypeIfPresent,
  )
  try
    if_present.process_delta(
      StreamingToolCallDelta::new(
        index=0,
        id="call-if-present",
        tool_type="custom",
        function_name="lookup",
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_eq(message, "Expected 'function' type.")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an invalid type error")
  }
  let required = StreamingToolCallTracker::new(
    type_validation=RequireFunctionToolCallType,
  )
  try
    required.process_delta(
      StreamingToolCallDelta::new(
        index=0,
        id="call-required",
        function_name="lookup",
      ),
    )
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_eq(message, "Expected 'function' type.")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a required type error")
  }
}

///|
test "streaming tool call tracker ignores late deltas and repeated flushes" {
  let tracker = StreamingToolCallTracker::new()
  let _ = tracker.process_delta(
    StreamingToolCallDelta::new(
      id="call-1",
      function_name="lookup",
      arguments_delta="{}",
    ),
  )
  assert_eq(tracker.flush().length(), 2)
  assert_eq(
    tracker
    .process_delta(StreamingToolCallDelta::new(index=0, arguments_delta="late"))
    .length(),
    0,
  )
  assert_eq(tracker.flush().length(), 0)
  assert_eq(tracker.calls()[0].arguments, "{}")
}

///|
test "streaming tool call tracker carries first-delta provider metadata" {
  let tracker = StreamingToolCallTracker::new()
  let _ = tracker.process_delta(
    StreamingToolCallDelta::new(
      index=0,
      id="call-1",
      function_name="lookup",
      arguments_delta="{}",
      provider_metadata={ "google": { "thoughtSignature": "sig-1" } },
    ),
  )
  let _ = tracker.process_delta(
    StreamingToolCallDelta::new(index=0, provider_metadata={
      "google": { "thoughtSignature": "ignored" },
    }),
  )
  let terminal = tracker.flush()
  assert_true(
    terminal[1]
    is @provider.ToolCallReady(
      {
        provider_metadata: { "google": { "thoughtSignature": "sig-1", .. }, .. },
        ..,
      }
    ),
  )
}

///|
test "streaming tool call tracker extracts and builds provider metadata" {
  let build_count = Ref(0)
  let tracker = StreamingToolCallTracker::new(
    extract_metadata=delta => {
      match delta.data {
        { "signature": String(value), .. } =>
          Map([("thoughtSignature", Json::string(value))])
        _ => Map([])
      }
    },
    build_tool_call_provider_metadata=metadata => {
      build_count.val = build_count.val + 1
      Map([("google", Json::object(metadata))])
    },
  )
  let _ = tracker.process_delta(
    StreamingToolCallDelta::new(index=0, id="call-1", function_name="lookup", data={
      "signature": "sig-1",
    }),
  )
  let terminal = tracker.flush()
  assert_true(
    terminal[1]
    is @provider.ToolCallReady(
      {
        provider_metadata: { "google": { "thoughtSignature": "sig-1", .. }, .. },
        ..,
      }
    ),
  )
  let _ = tracker.calls()
  let _ = tracker.calls()
  let _ = tracker.flush()
  assert_eq(build_count.val, 1)
}

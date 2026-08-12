///|
test "bridge commands encode start fields and boolean controls" {
  json_inspect(
    HarnessBridgeStart(
      prompt="hello",
      tools=[
        HarnessV1ToolSpec::new(name="weather", description="Read weather", input_schema={
          "type": "object",
        }),
      ],
      model=Some("model-1"),
      permission_mode=Some(HarnessAllowReads),
      tool_filtering=Some(HarnessAllowTools(["read", "grep"])),
      extension={ "thinking": "high" },
    ).to_json(),
    content={
      "type": "start",
      "prompt": "hello",
      "tools": [
        {
          "name": "weather",
          "description": "Read weather",
          "inputSchema": { "type": "object" },
        },
      ],
      "model": "model-1",
      "permissionMode": "allow-reads",
      "builtinToolFiltering": { "mode": "allow", "toolNames": ["read", "grep"] },
      "thinking": "high",
    },
  )
  json_inspect(
    HarnessBridgeToolApproval(
      approval_id="approval-1",
      approved=false,
      reason=Some("denied"),
    ).to_json(),
    content={
      "type": "tool-approval-response",
      "approvalId": "approval-1",
      "approved": false,
      "reason": "denied",
    },
  )
}

///|
test "bridge outbound decoder separates controls from stream events" {
  assert_eq(
    decode_harness_v1_bridge_outbound_frame(
      ({ "type": "bridge-hello", "state": "waiting", "lastSeq": 9 } : Json).stringify(),
    ),
    HarnessBridgeHello(state=Some("waiting"), last_seq=Some(9)),
  )
  assert_eq(
    decode_harness_v1_bridge_outbound_frame(
      (
        { "type": "text-delta", "seq": 4, "id": "text-1", "delta": "moon" } :
        Json).stringify(),
    ),
    HarnessBridgeStreamPart(
      seq=Some(4),
      part=HarnessTextDelta(id="text-1", delta="moon", harness_metadata=Map([])),
    ),
  )
}

///|
async test "bridge session sends controls and tracks delivered cursor" {
  let sent : Array[String] = []
  let frames : Array[String] = [
    ({ "type": "bridge-hello", "state": "waiting", "lastSeq": 0 } : Json).stringify(),
    ({ "type": "text-start", "seq": 1, "id": "text-1" } : Json).stringify(),
    ({ "type": "text-delta", "seq": 2, "id": "text-1", "delta": "hello" } : Json).stringify(),
    ({ "type": "text-end", "seq": 3, "id": "text-1" } : Json).stringify(),
    (
      {
        "type": "finish",
        "seq": 4,
        "finishReason": { "unified": "stop", "raw": "stop" },
        "totalUsage": {
          "inputTokens": { "total": 2 },
          "outputTokens": { "total": 1 },
        },
      } : Json).stringify(),
  ]
  let next = Ref(0)
  let connection = CallbackHarnessV1BridgeConnection::new(
    send=message => sent.push(message),
    receive=() => {
      if next.val >= frames.length() {
        return None
      }
      let value = frames[next.val]
      next.val = next.val + 1
      Some(value)
    },
  )
  let session = HarnessV1BridgeSession::new(
    session_id="session-1",
    harness_id="fixture",
    connection=connection as &HarnessV1BridgeConnection,
    model_id="model-1",
    permission_mode=HarnessAllowReads,
    tool_filtering=HarnessDenyTools(["bash"]),
  )
  let events : Array[HarnessV1StreamPart] = []
  let control = (session as &HarnessV1Session).do_prompt_turn(
    HarnessV1PromptTurnOptions::new(
      prompt=HarnessV1Prompt::text("hello"),
      emit=event => events.push(event),
      instructions="Use MoonBit",
    ),
  )
  control.submit_tool_result(
    HarnessV1ToolResultSubmission::new(tool_call_id="call-1", output={
      "ok": true,
    }),
  )
  control.done()
  assert_eq(sent.length(), 2)
  assert_true(
    @json.parse(sent[0])
    is {
      "type": "start",
      "prompt": "hello",
      "instructions": "Use MoonBit",
      "permissionMode": "allow-reads",
      ..
    },
  )
  assert_true(
    @json.parse(sent[1])
    is { "type": "tool-result", "toolCallId": "call-1", .. },
  )
  assert_eq(events.length(), 4)
  assert_eq(session.bridge_state().last_seen_event_id(), 4)
}

///|
test "prompt text conversion rejects assistant messages" {
  assert_eq(HarnessV1Prompt::text("hello").to_text(), "hello")
  try
    HarnessUserMessage(@provider_utils.ModelMessage::assistant("no")).to_text()
  catch {
    HarnessCapabilityUnsupportedError(..) => ()
  } noraise {
    _ => fail("expected assistant prompt to be rejected")
  }
}

///|
async test "workflow harness bridge folds a prompt turn into a step result" {
  let frames : Array[String] = [
    ({ "type": "bridge-hello", "state": "waiting", "lastSeq": 0 } : Json).stringify(),
    ({ "type": "text-start", "seq": 1, "id": "text-1" } : Json).stringify(),
    ({ "type": "text-delta", "seq": 2, "id": "text-1", "delta": "hello" } : Json).stringify(),
    ({ "type": "text-delta", "seq": 3, "id": "text-1", "delta": " moon" } : Json).stringify(),
    ({ "type": "text-end", "seq": 4, "id": "text-1" } : Json).stringify(),
    (
      {
        "type": "finish",
        "seq": 5,
        "finishReason": { "unified": "stop", "raw": "stop" },
        "totalUsage": {
          "inputTokens": { "total": 2 },
          "outputTokens": { "total": 1 },
        },
      } : Json).stringify(),
  ]
  let next = Ref(0)
  let connection = @harness.CallbackHarnessV1BridgeConnection::new(
    send=_ => (),
    receive=() => {
      if next.val >= frames.length() {
        return None
      }
      let value = frames[next.val]
      next.val = next.val + 1
      Some(value)
    },
  )
  let session = @harness.HarnessV1BridgeSession::new(
    session_id="session-1",
    harness_id="fixture",
    connection=connection as &@harness.HarnessV1BridgeConnection,
    model_id="model-1",
    permission_mode=@harness.HarnessAllowReads,
  )
  let bridge = WorkflowHarnessBridge::new(
    session=session as &@harness.HarnessV1Session,
  )
  let result = bridge.run_prompt_turn(prompt="fix the bug")
  assert_eq(result.text, "hello moon")
  assert_eq(result.tool_inputs_started, 0)
  assert_eq(result.events, 5)
}

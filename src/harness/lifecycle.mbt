///|
/// A built-in or host tool waiting for an approval decision.
pub(all) struct HarnessV1PendingToolApproval {
  approval_id : String
  tool_call_id : String
  tool_name : String
  input : String
  kind : String
  provider_executed : Bool
  native_name : String?
} derive(Debug, Eq)

///|
/// A host tool call waiting for its result.
pub(all) struct HarnessV1PendingToolResult {
  tool_call_id : String
  tool_name : String
  input : String
} derive(Debug, Eq)

///|
/// Opaque state for a session that can accept a future prompt.
pub(all) struct HarnessV1ResumeSessionState {
  harness_id : String
  specification_version : String
  data : Json
  continue_from : HarnessV1ContinueTurnState?
} derive(Debug, Eq)

///|
/// Opaque state for a suspended in-flight turn.
pub(all) struct HarnessV1ContinueTurnState {
  harness_id : String
  specification_version : String
  data : Json
  pending_tool_approvals : Array[HarnessV1PendingToolApproval]
  pending_tool_results : Array[HarnessV1PendingToolResult]
} derive(Debug, Eq)

///|
/// Construct a resumable between-turn state value.
pub fn HarnessV1ResumeSessionState::new(
  harness_id~ : String,
  data? : Json = Json::empty_object(),
  continue_from? : HarnessV1ContinueTurnState,
) -> HarnessV1ResumeSessionState {
  {
    harness_id,
    specification_version: HARNESS_V1_SPECIFICATION_VERSION,
    data,
    continue_from,
  }
}

///|
/// Construct a resumable suspended-turn state value.
pub fn HarnessV1ContinueTurnState::new(
  harness_id~ : String,
  data? : Json = Json::empty_object(),
  pending_tool_approvals? : Array[HarnessV1PendingToolApproval] = [],
  pending_tool_results? : Array[HarnessV1PendingToolResult] = [],
) -> HarnessV1ContinueTurnState {
  {
    harness_id,
    specification_version: HARNESS_V1_SPECIFICATION_VERSION,
    data,
    pending_tool_approvals: pending_tool_approvals.copy(),
    pending_tool_results: pending_tool_results.copy(),
  }
}

///|
/// Validate that lifecycle state belongs to the receiving adapter.
pub fn validate_harness_v1_lifecycle_state(
  harness_id : String,
  state_harness_id : String,
  specification_version : String,
) -> Unit raise HarnessError {
  guard state_harness_id == harness_id else {
    raise harness_error(
      "Harness lifecycle state belongs to '" +
      state_harness_id +
      "', not '" +
      harness_id +
      "'",
    )
  }
  guard specification_version == HARNESS_V1_SPECIFICATION_VERSION else {
    raise harness_error(
      "Unsupported harness lifecycle specification: " + specification_version,
    )
  }
}

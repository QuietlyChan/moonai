///|
/// A host tool result submitted to an active harness turn.
pub(all) struct HarnessV1ToolResultSubmission {
  tool_call_id : String
  output : Json
  is_error : Bool
} derive(Debug, Eq)

///|
/// Construct a host tool result submission.
pub fn HarnessV1ToolResultSubmission::new(
  tool_call_id~ : String,
  output~ : Json,
  is_error? : Bool = false,
) -> HarnessV1ToolResultSubmission {
  { tool_call_id, output, is_error }
}

///|
/// A host decision for an adapter-native tool approval request.
pub(all) struct HarnessV1ToolApprovalSubmission {
  approval_id : String
  approved : Bool
  reason : String?
} derive(Debug, Eq)

///|
/// Construct a tool approval decision.
pub fn HarnessV1ToolApprovalSubmission::new(
  approval_id~ : String,
  approved~ : Bool,
  reason? : String,
) -> HarnessV1ToolApprovalSubmission {
  { approval_id, approved, reason }
}

///|
/// Bidirectional control surface for one active harness turn.
///
/// `done` performs the receive loop in the caller's task. This follows
/// MoonBit structured concurrency: callers can run `done` beside tool-result
/// and approval producers in their own task group without an orphan task.
pub struct HarnessV1PromptControl {
  priv submit_tool_result_callback : async (HarnessV1ToolResultSubmission) -> Unit
  priv submit_tool_approval_callback : async (HarnessV1ToolApprovalSubmission) -> Unit
  priv submit_user_message_callback : async (String) -> Unit
  priv done_callback : async () -> Unit
}

///|
/// Construct a prompt-control handle from runtime callbacks.
pub fn HarnessV1PromptControl::new(
  submit_tool_result~ : async (HarnessV1ToolResultSubmission) -> Unit,
  done~ : async () -> Unit,
  submit_tool_approval? : async (HarnessV1ToolApprovalSubmission) -> Unit = _ => {
    raise HarnessCapabilityUnsupportedError::new(
      message="This harness does not support built-in tool approvals",
    )
  },
  submit_user_message? : async (String) -> Unit = _ => {
    raise HarnessCapabilityUnsupportedError::new(
      message="This harness does not support mid-turn user messages",
    )
  },
) -> HarnessV1PromptControl {
  {
    submit_tool_result_callback: submit_tool_result,
    submit_tool_approval_callback: submit_tool_approval,
    submit_user_message_callback: submit_user_message,
    done_callback: done,
  }
}

///|
/// Submit a host tool result to the runtime.
pub async fn HarnessV1PromptControl::submit_tool_result(
  self : HarnessV1PromptControl,
  input : HarnessV1ToolResultSubmission,
) -> Unit {
  (self.submit_tool_result_callback)(input)
}

///|
/// AI SDK-style spelling for `submit_tool_result`.
pub async fn HarnessV1PromptControl::submitToolResult(
  self : HarnessV1PromptControl,
  input : HarnessV1ToolResultSubmission,
) -> Unit {
  self.submit_tool_result(input)
}

///|
/// Submit a tool approval decision to the runtime.
pub async fn HarnessV1PromptControl::submit_tool_approval(
  self : HarnessV1PromptControl,
  input : HarnessV1ToolApprovalSubmission,
) -> Unit {
  (self.submit_tool_approval_callback)(input)
}

///|
/// AI SDK-style spelling for `submit_tool_approval`.
pub async fn HarnessV1PromptControl::submitToolApproval(
  self : HarnessV1PromptControl,
  input : HarnessV1ToolApprovalSubmission,
) -> Unit {
  self.submit_tool_approval(input)
}

///|
/// Inject a fresh user message into an active turn.
pub async fn HarnessV1PromptControl::submit_user_message(
  self : HarnessV1PromptControl,
  text : String,
) -> Unit {
  (self.submit_user_message_callback)(text)
}

///|
/// AI SDK-style spelling for `submit_user_message`.
pub async fn HarnessV1PromptControl::submitUserMessage(
  self : HarnessV1PromptControl,
  text : String,
) -> Unit {
  self.submit_user_message(text)
}

///|
/// Consume the turn until it finishes or fails.
pub async fn HarnessV1PromptControl::done(
  self : HarnessV1PromptControl,
) -> Unit {
  (self.done_callback)()
}

///|
/// Options used to create or resume a harness session.
pub(all) struct HarnessV1StartOptions {
  session_id : String
  skills : Array[HarnessV1Skill]
  resume_from : HarnessV1ResumeSessionState?
  continue_from : HarnessV1ContinueTurnState?
  permission_mode : HarnessV1PermissionMode?
  builtin_tool_filtering : HarnessV1BuiltinToolFiltering?
  cancellation_token : @provider.CancellationToken?
  observability : HarnessV1Observability?
  sandbox_session : HarnessV1NetworkSandboxSession
  session_work_dir : String
}

///|
/// Construct harness session start options.
pub fn HarnessV1StartOptions::new(
  session_id~ : String,
  sandbox_session~ : HarnessV1NetworkSandboxSession,
  session_work_dir~ : String,
  skills? : Array[HarnessV1Skill] = [],
  resume_from? : HarnessV1ResumeSessionState,
  continue_from? : HarnessV1ContinueTurnState,
  permission_mode? : HarnessV1PermissionMode,
  builtin_tool_filtering? : HarnessV1BuiltinToolFiltering,
  cancellation_token? : @provider.CancellationToken,
  observability? : HarnessV1Observability,
) -> HarnessV1StartOptions {
  {
    session_id,
    skills: skills.copy(),
    resume_from,
    continue_from,
    permission_mode,
    builtin_tool_filtering,
    cancellation_token,
    observability,
    sandbox_session,
    session_work_dir,
  }
}

///|
/// Options for a fresh prompt turn.
pub(all) struct HarnessV1PromptTurnOptions {
  prompt : HarnessV1Prompt
  tools : Array[HarnessV1ToolSpec]
  instructions : String?
  cancellation_token : @provider.CancellationToken?
  emit : (HarnessV1StreamPart) -> Unit
}

///|
/// Construct prompt-turn options.
pub fn HarnessV1PromptTurnOptions::new(
  prompt~ : HarnessV1Prompt,
  emit~ : (HarnessV1StreamPart) -> Unit,
  tools? : Array[HarnessV1ToolSpec] = [],
  instructions? : String,
  cancellation_token? : @provider.CancellationToken,
) -> HarnessV1PromptTurnOptions {
  { prompt, tools: tools.copy(), instructions, cancellation_token, emit }
}

///|
/// Options for continuing a previously suspended in-flight turn.
pub(all) struct HarnessV1ContinueTurnOptions {
  tools : Array[HarnessV1ToolSpec]
  cancellation_token : @provider.CancellationToken?
  emit : (HarnessV1StreamPart) -> Unit
}

///|
/// Construct continue-turn options.
pub fn HarnessV1ContinueTurnOptions::new(
  emit~ : (HarnessV1StreamPart) -> Unit,
  tools? : Array[HarnessV1ToolSpec] = [],
  cancellation_token? : @provider.CancellationToken,
) -> HarnessV1ContinueTurnOptions {
  { tools: tools.copy(), cancellation_token, emit }
}

///|
/// Active stateful harness session.
pub(open) trait HarnessV1Session {
  fn session_id(Self) -> String
  fn is_resume(Self) -> Bool
  fn model_id(Self) -> String?
  async fn do_prompt_turn(Self, HarnessV1PromptTurnOptions) -> HarnessV1PromptControl
  async fn do_compact(Self, String?) -> Unit
  async fn do_continue_turn(Self, HarnessV1ContinueTurnOptions) -> HarnessV1PromptControl
  async fn do_suspend_turn(Self) -> HarnessV1ContinueTurnState
  async fn do_detach(Self) -> HarnessV1ResumeSessionState
  async fn do_stop(Self) -> HarnessV1ResumeSessionState
  async fn do_destroy(Self) -> Unit
}

///|
/// Versioned coding-agent runtime adapter.
pub(open) trait HarnessV1 {
  fn specification_version(Self) -> String
  fn harness_id(Self) -> String
  fn builtin_tools(Self) -> Array[HarnessV1BuiltinTool]
  fn supports_builtin_tool_approvals(Self) -> Bool
  fn supports_builtin_tool_filtering(Self) -> Bool
  async fn get_bootstrap(Self) -> HarnessV1Bootstrap?
  async fn do_start(Self, HarnessV1StartOptions) -> &HarnessV1Session
}

///|
/// Call `do_start` on a harness trait object.
pub async fn start_harness_v1(
  harness : &HarnessV1,
  options : HarnessV1StartOptions,
) -> &HarnessV1Session {
  harness.do_start(options)
}

///|
/// AI SDK-style spelling for `start_harness_v1`.
pub async fn startHarnessV1(
  harness : &HarnessV1,
  options : HarnessV1StartOptions,
) -> &HarnessV1Session {
  start_harness_v1(harness, options)
}

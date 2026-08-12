///|
/// Shared session implementation for WebSocket and stdio harness bridges.
///
/// Adapter packages only provide bridge coordinates and adapter-specific
/// start fields. All lifecycle and bidirectional control behavior lives here.
pub struct HarnessV1BridgeSession {
  priv session_id_value : String
  priv harness_id_value : String
  priv model_id_value : String?
  priv resume_value : Bool
  priv permission_mode_value : HarnessV1PermissionMode?
  priv tool_filtering_value : HarnessV1BuiltinToolFiltering?
  priv bridge_state : HarnessV1BridgeState
  priv extension_value : Map[String, Json]
  priv stopped : Ref[Bool]
  priv instructions_applied : Ref[Bool]
}

///|
/// Construct a shared bridge-backed harness session.
pub fn HarnessV1BridgeSession::new(
  session_id~ : String,
  harness_id~ : String,
  connection~ : &HarnessV1BridgeConnection,
  model_id? : String,
  resumed? : Bool = false,
  last_seen_event_id? : Int = 0,
  extension? : Map[String, Json] = Map([]),
  permission_mode? : HarnessV1PermissionMode,
  tool_filtering? : HarnessV1BuiltinToolFiltering,
  diagnostic_reporter? : HarnessV1DiagnosticReporter,
) -> HarnessV1BridgeSession {
  {
    session_id_value: session_id,
    harness_id_value: harness_id,
    model_id_value: model_id,
    resume_value: resumed,
    permission_mode_value: permission_mode,
    tool_filtering_value: tool_filtering,
    bridge_state: HarnessV1BridgeState::new(
      connection,
      last_seen_event_id~,
      diagnostic_reporter?,
      session_id~,
    ),
    extension_value: extension.copy(),
    stopped: Ref(false),
    instructions_applied: Ref(resumed),
  }
}

///|
/// Return the bridge state for advanced integrations and tests.
pub fn HarnessV1BridgeSession::bridge_state(
  self : HarnessV1BridgeSession,
) -> HarnessV1BridgeState {
  self.bridge_state
}

///|
fn HarnessV1BridgeSession::make_control(
  self : HarnessV1BridgeSession,
  emit : (HarnessV1StreamPart) -> Unit,
  cancellation_token : @provider.CancellationToken?,
) -> HarnessV1PromptControl {
  let state = self.bridge_state
  let submit_tool_result : async (HarnessV1ToolResultSubmission) -> Unit = input => {
    @provider.check_cancellation(cancellation_token)
    state.send(
      HarnessBridgeToolResult(
        tool_call_id=input.tool_call_id,
        output=input.output,
        is_error=input.is_error,
      ),
    )
  }
  let submit_tool_approval : async (HarnessV1ToolApprovalSubmission) -> Unit = input => {
    @provider.check_cancellation(cancellation_token)
    state.send(
      HarnessBridgeToolApproval(
        approval_id=input.approval_id,
        approved=input.approved,
        reason=input.reason,
      ),
    )
  }
  let submit_user_message : async (String) -> Unit = text => {
    @provider.check_cancellation(cancellation_token)
    state.send(HarnessBridgeUserMessage(text))
  }
  let done : async () -> Unit = () => {
    @provider.check_cancellation(cancellation_token)
    state.consume(emit)
  }
  HarnessV1PromptControl::new(
    submit_tool_result~,
    done~,
    submit_tool_approval~,
    submit_user_message~,
  )
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn session_id(self) {
  self.session_id_value
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn is_resume(self) {
  self.resume_value
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn model_id(self) {
  self.model_id_value
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn do_prompt_turn(
  self,
  options,
) {
  guard !self.stopped.val else {
    raise HarnessError(message="Harness session is stopped", cause=None)
  }
  @provider.check_cancellation(options.cancellation_token)
  let extension = self.extension_value.copy()
  if options.instructions is Some(instructions) &&
    !self.instructions_applied.val {
    extension["instructions"] = Json::string(instructions)
    self.instructions_applied.val = true
  }
  self.bridge_state.send(
    HarnessBridgeStart(
      prompt=options.prompt.to_text() catch { error => raise error },
      tools=options.tools,
      model=self.model_id_value,
      permission_mode=self.permission_mode_value,
      tool_filtering=self.tool_filtering_value,
      extension~,
    ),
  )
  self.make_control(options.emit, options.cancellation_token)
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn do_compact(
  _self,
  _custom_instructions,
) {
  raise HarnessCapabilityUnsupportedError::new(
    message="This bridge adapter does not expose manual compaction",
  )
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn do_continue_turn(
  self,
  options,
) {
  guard !self.stopped.val else {
    raise HarnessError(message="Harness session is stopped", cause=None)
  }
  @provider.check_cancellation(options.cancellation_token)
  self.make_control(options.emit, options.cancellation_token)
}

///|
async fn HarnessV1BridgeSession::send_detach_and_wait(
  self : HarnessV1BridgeSession,
) -> Unit {
  self.bridge_state.send(HarnessBridgeDetach)
  self.bridge_state.consume(_ => ())
}

///|
fn HarnessV1BridgeSession::lifecycle_data(
  self : HarnessV1BridgeSession,
) -> Json {
  let fields : Map[String, Json] = Map([
    (
      "lastSeenEventId",
      Json::number(self.bridge_state.last_seen_event_id().to_double()),
    ),
  ])
  if self.bridge_state.thread_id() is Some(thread_id) {
    fields["threadId"] = Json::string(thread_id)
  }
  if self.bridge_state.detach_data() is Some(data) {
    fields["bridgeData"] = data
  }
  Json::object(fields)
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn do_suspend_turn(
  self,
) {
  guard !self.stopped.val else {
    raise HarnessError(message="Harness session is stopped", cause=None)
  }
  self.bridge_state.send(HarnessBridgeSuspend)
  self.bridge_state.close()
  self.stopped.val = true
  HarnessV1ContinueTurnState::new(
    harness_id=self.harness_id_value,
    data=self.lifecycle_data(),
  )
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn do_detach(self) {
  guard !self.stopped.val else {
    raise HarnessError(message="Harness session is already stopped", cause=None)
  }
  self.send_detach_and_wait()
  self.stopped.val = true
  self.bridge_state.close()
  HarnessV1ResumeSessionState::new(
    harness_id=self.harness_id_value,
    data=self.lifecycle_data(),
  )
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn do_stop(self) {
  if !self.stopped.val {
    self.stopped.val = true
    self.bridge_state.send(HarnessBridgeShutdown) catch {
      _ => ()
    }
    self.bridge_state.close()
  }
  HarnessV1ResumeSessionState::new(
    harness_id=self.harness_id_value,
    data=self.lifecycle_data(),
  )
}

///|
pub impl HarnessV1Session for HarnessV1BridgeSession with fn do_destroy(self) {
  if !self.stopped.val {
    self.stopped.val = true
    self.bridge_state.send(HarnessBridgeShutdown) catch {
      _ => ()
    }
    self.bridge_state.close()
  }
}

///|
/// A bidirectional connection to a harness bridge.
///
/// The bridge protocol uses one JSON object per frame. Implementations may
/// use WebSocket, persistent stdio, or a test fixture; adapters depend only on
/// this small transport surface.
pub(open) trait HarnessV1BridgeConnection {
  async fn send(Self, String) -> Unit
  async fn receive(Self) -> String?
  fn close(Self) -> Unit
}

///|
/// Create a bridge connection from callbacks, useful for custom transports and
/// deterministic tests.
pub struct CallbackHarnessV1BridgeConnection {
  send_callback : async (String) -> Unit
  receive_callback : async () -> String?
  close_callback : () -> Unit
}

///|
/// Construct a callback-backed bridge connection.
pub fn CallbackHarnessV1BridgeConnection::new(
  send~ : async (String) -> Unit,
  receive~ : async () -> String?,
  close? : () -> Unit = () => (),
) -> CallbackHarnessV1BridgeConnection {
  { send_callback: send, receive_callback: receive, close_callback: close }
}

///|
pub impl HarnessV1BridgeConnection for CallbackHarnessV1BridgeConnection with fn send(
  self,
  message,
) {
  (self.send_callback)(message)
}

///|
pub impl HarnessV1BridgeConnection for CallbackHarnessV1BridgeConnection with fn receive(
  self,
) {
  (self.receive_callback)()
}

///|
pub impl HarnessV1BridgeConnection for CallbackHarnessV1BridgeConnection with fn close(
  self,
) {
  (self.close_callback)()
}

///|
/// Bridge command accepted by all bridge-backed adapters.
pub(all) enum HarnessV1BridgeCommand {
  HarnessBridgeStart(
    prompt~ : String,
    tools~ : Array[HarnessV1ToolSpec],
    model~ : String?,
    permission_mode~ : HarnessV1PermissionMode?,
    tool_filtering~ : HarnessV1BuiltinToolFiltering?,
    extension~ : Map[String, Json]
  )
  HarnessBridgeToolResult(
    tool_call_id~ : String,
    output~ : Json,
    is_error~ : Bool
  )
  HarnessBridgeToolApproval(
    approval_id~ : String,
    approved~ : Bool,
    reason~ : String?
  )
  HarnessBridgeUserMessage(String)
  HarnessBridgeAbort
  HarnessBridgeShutdown
  HarnessBridgeResume(last_seen_event_id~ : Int)
  HarnessBridgeDetach
  HarnessBridgeSuspend
} derive(Debug, Eq)

///|
/// Serialize a bridge command to its NDJSON payload.
pub fn HarnessV1BridgeCommand::to_json(self : HarnessV1BridgeCommand) -> Json {
  match self {
    HarnessBridgeStart(
      prompt~,
      tools~,
      model~,
      permission_mode~,
      tool_filtering~,
      extension~
    ) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("start")),
        ("prompt", Json::string(prompt)),
      ])
      if tools.length() > 0 {
        fields["tools"] = [
          for tool in tools => {
            let tool_fields : Map[String, Json] = Map([
              ("name", Json::string(tool.name)),
            ])
            if tool.description is Some(value) {
              tool_fields["description"] = Json::string(value)
            }
            if tool.input_schema is Some(value) {
              tool_fields["inputSchema"] = value
            }
            Json::object(tool_fields)
          }
        ]
      }
      if model is Some(value) {
        fields["model"] = Json::string(value)
      }
      if permission_mode is Some(value) {
        fields["permissionMode"] = Json::string(value.to_string())
      }
      if tool_filtering is Some(value) {
        match value {
          HarnessAllowTools(names) =>
            fields["builtinToolFiltering"] = {
              "mode": "allow",
              "toolNames": names,
            }
          HarnessDenyTools(names) =>
            fields["builtinToolFiltering"] = {
              "mode": "deny",
              "toolNames": names,
            }
        }
      }
      for entry in extension.iter2() {
        fields[entry.0] = entry.1
      }
      Json::object(fields)
    }
    HarnessBridgeToolResult(tool_call_id~, output~, is_error~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("tool-result")),
        ("toolCallId", Json::string(tool_call_id)),
        ("output", output),
      ])
      if is_error {
        fields["isError"] = Json::boolean(true)
      }
      Json::object(fields)
    }
    HarnessBridgeToolApproval(approval_id~, approved~, reason~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("tool-approval-response")),
        ("approvalId", Json::string(approval_id)),
        ("approved", Json::boolean(approved)),
      ])
      if reason is Some(value) {
        fields["reason"] = Json::string(value)
      }
      Json::object(fields)
    }
    HarnessBridgeUserMessage(text) =>
      ({ "type": "user-message", "text": text } : Json)
    HarnessBridgeAbort => ({ "type": "abort" } : Json)
    HarnessBridgeShutdown => ({ "type": "shutdown" } : Json)
    HarnessBridgeResume(last_seen_event_id~) =>
      ({ "type": "resume", "lastSeenEventId": last_seen_event_id } : Json)
    HarnessBridgeDetach => ({ "type": "detach" } : Json)
    HarnessBridgeSuspend => ({ "type": "suspend" } : Json)
  }
}

///|
/// Send one JSON command on a bridge connection.
pub async fn send_harness_v1_bridge_command(
  connection : &HarnessV1BridgeConnection,
  command : HarnessV1BridgeCommand,
) -> Unit {
  connection.send(command.to_json().stringify())
}

///|
/// One validated frame emitted by a harness bridge.
pub(all) enum HarnessV1BridgeOutboundFrame {
  HarnessBridgeStreamPart(seq~ : Int?, part~ : HarnessV1StreamPart)
  HarnessBridgeHello(state~ : String?, last_seq~ : Int?)
  HarnessBridgeDetached(data~ : Json)
  HarnessBridgeThread(thread_id~ : String)
  HarnessBridgeSandboxLog(
    seq~ : Int?,
    source~ : String,
    stream~ : String,
    line~ : String
  )
  HarnessBridgeDebugEvent(
    seq~ : Int?,
    level~ : HarnessV1DebugLevel,
    subsystem~ : String,
    message~ : String,
    attrs~ : Json?,
    error~ : Json?
  )
  HarnessBridgeReady(port~ : Int)
} derive(Debug, Eq)

///|
/// Runtime state maintained by a bridge session.
pub struct HarnessV1BridgeState {
  priv connection : &HarnessV1BridgeConnection
  priv last_seen_event_id : Ref[Int]
  priv bridge_last_seq : Ref[Int]
  priv thread_id_value : Ref[String?]
  priv detach_data_value : Ref[Json?]
  priv lifecycle_state_value : Ref[String?]
  priv diagnostic_reporter : HarnessV1DiagnosticReporter?
  priv session_id_value : String?
  priv closed : Ref[Bool]
}

///|
/// Construct a bridge state holder.
pub fn HarnessV1BridgeState::new(
  connection : &HarnessV1BridgeConnection,
  last_seen_event_id? : Int = 0,
  diagnostic_reporter? : HarnessV1DiagnosticReporter,
  session_id? : String,
) -> HarnessV1BridgeState {
  {
    connection,
    last_seen_event_id: Ref(last_seen_event_id),
    bridge_last_seq: Ref(last_seen_event_id),
    thread_id_value: Ref(None),
    detach_data_value: Ref(None),
    lifecycle_state_value: Ref(None),
    diagnostic_reporter,
    session_id_value: session_id,
    closed: Ref(false),
  }
}

///|
/// Return the highest bridge sequence observed by this state holder.
pub fn HarnessV1BridgeState::last_seen_event_id(
  self : HarnessV1BridgeState,
) -> Int {
  self.last_seen_event_id.val
}

///|
/// Return the highest sequence announced by the remote bridge.
pub fn HarnessV1BridgeState::remote_last_seq(
  self : HarnessV1BridgeState,
) -> Int {
  self.bridge_last_seq.val
}

///|
/// Return the latest runtime thread coordinate announced by the bridge.
pub fn HarnessV1BridgeState::thread_id(self : HarnessV1BridgeState) -> String? {
  self.thread_id_value.val
}

///|
/// Return the most recent detach payload received from the bridge.
pub fn HarnessV1BridgeState::detach_data(self : HarnessV1BridgeState) -> Json? {
  self.detach_data_value.val
}

///|
/// Return the lifecycle state reported in the bridge handshake.
pub fn HarnessV1BridgeState::lifecycle_state(
  self : HarnessV1BridgeState,
) -> String? {
  self.lifecycle_state_value.val
}

///|
/// Send a command through this bridge state holder.
pub async fn HarnessV1BridgeState::send(
  self : HarnessV1BridgeState,
  command : HarnessV1BridgeCommand,
) -> Unit raise HarnessError {
  guard !self.closed.val else {
    raise harness_error("Harness bridge connection is closed")
  }
  send_harness_v1_bridge_command(self.connection, command) catch {
    error =>
      raise HarnessError(
        message="Failed to send harness bridge command",
        cause=Some(@debug.to_string(error)),
      )
  }
}

///|
/// Close the bridge connection. This operation is idempotent.
pub fn HarnessV1BridgeState::close(self : HarnessV1BridgeState) -> Unit {
  if !self.closed.val {
    self.closed.val = true
    self.connection.close()
  }
}

///|
/// Decode one bridge outbound frame. Malformed frames raise `HarnessError`
/// rather than silently becoming raw events because bridges are trust
/// boundaries.
pub fn decode_harness_v1_bridge_frame(
  text : String,
) -> HarnessV1StreamPart raise HarnessError {
  let json = @json.parse(text) catch {
    error =>
      raise HarnessError(
        message="Failed to parse harness bridge JSON",
        cause=Some(@debug.to_string(error)),
      )
  }
  decode_harness_v1_bridge_json(json)
}

///|
/// Decode every frame in the shared bridge protocol, including transport and
/// diagnostic control frames that are not consumer stream events.
pub fn decode_harness_v1_bridge_outbound_frame(
  text : String,
) -> HarnessV1BridgeOutboundFrame raise HarnessError {
  let json = @json.parse(text) catch {
    error =>
      raise HarnessError(
        message="Failed to parse harness bridge JSON",
        cause=Some(@debug.to_string(error)),
      )
  }
  guard json is Object(fields) else {
    raise harness_error("Harness bridge frame must be an object")
  }
  guard fields.get("type") is Some(String(kind)) else {
    raise harness_error("Harness bridge frame must contain string type")
  }
  let seq = json_optional_int(fields, "seq")
  match kind {
    "bridge-hello" =>
      HarnessBridgeHello(
        state=json_optional_string(fields, "state"),
        last_seq=json_optional_int(fields, "lastSeq"),
      )
    "bridge-detach" =>
      HarnessBridgeDetached(
        data=fields.get("data").unwrap_or(Json::empty_object()),
      )
    "bridge-thread" =>
      HarnessBridgeThread(thread_id=json_required_string(fields, "threadId"))
    "sandbox-log" => {
      let stream = json_required_string(fields, "stream")
      guard stream == "stdout" || stream == "stderr" else {
        raise harness_error(
          "Harness sandbox-log stream must be stdout or stderr",
        )
      }
      HarnessBridgeSandboxLog(
        seq~,
        source=json_required_string(fields, "source"),
        stream~,
        line=json_required_string(fields, "line"),
      )
    }
    "debug-event" =>
      HarnessBridgeDebugEvent(
        seq~,
        level=HarnessV1DebugLevel::from_string(
          json_required_string(fields, "level"),
        ),
        subsystem=json_required_string(fields, "subsystem"),
        message=json_required_string(fields, "message"),
        attrs=fields.get("attrs"),
        error=fields.get("error"),
      )
    "bridge-ready" => {
      guard json_optional_int(fields, "port") is Some(port) else {
        raise harness_error("Harness bridge-ready port must be a number")
      }
      HarnessBridgeReady(port~)
    }
    _ => HarnessBridgeStreamPart(seq~, part=decode_harness_v1_bridge_json(json))
  }
}

///|
/// Decode a parsed bridge outbound frame.
pub fn decode_harness_v1_bridge_json(
  json : Json,
) -> HarnessV1StreamPart raise HarnessError {
  guard json is Object(fields) else {
    raise harness_error("Harness bridge frame must be an object")
  }
  guard fields.get("type") is Some(String(kind)) else {
    raise harness_error("Harness bridge frame must contain string type")
  }
  match kind {
    "stream-start" =>
      HarnessStreamStart(
        warnings=decode_harness_warnings(fields.get("warnings")),
        model_id=json_optional_string(fields, "modelId"),
      )
    "text-start" =>
      HarnessTextStart(
        id=json_required_string(fields, "id"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "text-delta" =>
      HarnessTextDelta(
        id=json_required_string(fields, "id"),
        delta=json_required_string(fields, "delta"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "text-end" =>
      HarnessTextEnd(
        id=json_required_string(fields, "id"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "reasoning-start" =>
      HarnessReasoningStart(
        id=json_required_string(fields, "id"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "reasoning-delta" =>
      HarnessReasoningDelta(
        id=json_required_string(fields, "id"),
        delta=json_required_string(fields, "delta"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "reasoning-end" =>
      HarnessReasoningEnd(
        id=json_required_string(fields, "id"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "tool-call" =>
      HarnessToolCall(
        call=decode_harness_tool_call(fields),
        native_name=json_optional_string(fields, "nativeName"),
      )
    "tool-approval-request" =>
      HarnessToolApprovalRequest(decode_harness_tool_approval_request(fields))
    "tool-result" => HarnessToolResult(decode_harness_tool_result(fields))
    "finish-step" =>
      HarnessFinishStep(
        finish_reason=decode_harness_finish_reason(fields.get("finishReason")),
        usage=decode_harness_usage(fields.get("usage")),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "finish" =>
      HarnessFinish(
        finish_reason=decode_harness_finish_reason(fields.get("finishReason")),
        total_usage=decode_harness_usage(fields.get("totalUsage")),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "file-change" =>
      HarnessFileChange(
        event=HarnessV1FileChangeKind::from_string(
          json_required_string(fields, "event"),
        ),
        path=json_required_string(fields, "path"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "compaction" =>
      HarnessCompaction(
        trigger=HarnessV1CompactionTrigger::from_string(
          json_required_string(fields, "trigger"),
        ),
        summary=json_required_string(fields, "summary"),
        tokens_before=json_optional_int(fields, "tokensBefore"),
        tokens_after=json_optional_int(fields, "tokensAfter"),
        harness_metadata=decode_harness_metadata(fields.get("harnessMetadata")),
      )
    "error" =>
      HarnessStreamError(
        error=fields
          .get("error")
          .unwrap_or(Json::string("Unknown bridge error")),
      )
    "raw" =>
      HarnessRaw(
        raw_value=fields.get("rawValue").unwrap_or(Json::empty_object()),
      )
    _ => raise harness_error("Unsupported harness bridge frame type: " + kind)
  }
}

///|
fn json_required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise HarnessError {
  match fields.get(name) {
    Some(String(value)) => value
    _ =>
      raise harness_error(
        "Harness bridge field '" + name + "' must be a string",
      )
  }
}

///|
fn json_optional_string(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_optional_bool(fields : Map[String, Json], name : String) -> Bool {
  match fields.get(name) {
    Some(True) => true
    Some(False) => false
    _ => false
  }
}

///|
fn json_optional_int(fields : Map[String, Json], name : String) -> Int? {
  match fields.get(name) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn decode_harness_metadata(value : Json?) -> HarnessV1Metadata {
  match value {
    Some(Object(fields)) => fields
    _ => Map([])
  }
}

///|
fn decode_harness_warnings(value : Json?) -> Array[HarnessV1CallWarning] {
  let warnings : Array[HarnessV1CallWarning] = []
  match value {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(fields) =>
            match json_optional_string(fields, "type") {
              Some("unsupported-setting") =>
                warnings.push(
                  HarnessUnsupportedSetting(
                    setting=json_optional_string(fields, "setting").unwrap_or(
                      "",
                    ),
                    details=json_optional_string(fields, "details"),
                  ),
                )
              Some("unsupported-tool") =>
                warnings.push(
                  HarnessUnsupportedTool(
                    tool=json_optional_string(fields, "tool").unwrap_or(""),
                    details=json_optional_string(fields, "details"),
                  ),
                )
              Some("other") =>
                warnings.push(
                  HarnessOtherWarning(
                    message=json_optional_string(fields, "message").unwrap_or(
                      "",
                    ),
                  ),
                )
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  warnings
}

///|
fn decode_harness_tool_call(
  fields : Map[String, Json],
) -> @provider.LanguageModelV4ToolCall raise HarnessError {
  {
    tool_call_id: json_required_string(fields, "toolCallId"),
    tool_name: json_required_string(fields, "toolName"),
    input: json_required_string(fields, "input"),
    provider_executed: json_optional_bool(fields, "providerExecuted"),
    dynamic: json_optional_bool(fields, "dynamic"),
    provider_metadata: decode_harness_metadata(fields.get("providerMetadata")),
  }
}

///|
fn decode_harness_tool_approval_request(
  fields : Map[String, Json],
) -> @provider.LanguageModelV4ToolApprovalRequest raise HarnessError {
  {
    approval_id: json_required_string(fields, "approvalId"),
    tool_call_id: json_required_string(fields, "toolCallId"),
    provider_metadata: decode_harness_metadata(fields.get("providerMetadata")),
  }
}

///|
fn decode_harness_tool_result(
  fields : Map[String, Json],
) -> @provider.LanguageModelV4ToolResult raise HarnessError {
  {
    tool_call_id: json_required_string(fields, "toolCallId"),
    tool_name: json_required_string(fields, "toolName"),
    result: fields.get("result").unwrap_or(Json::null()),
    is_error: json_optional_bool(fields, "isError"),
    preliminary: json_optional_bool(fields, "preliminary"),
    dynamic: json_optional_bool(fields, "dynamic"),
    provider_metadata: decode_harness_metadata(fields.get("providerMetadata")),
  }
}

///|
fn decode_harness_finish_reason(
  value : Json?,
) -> @provider.LanguageModelV4FinishReason raise HarnessError {
  guard value is Some(Object(fields)) else {
    raise harness_error("Harness bridge finishReason must be an object")
  }
  let unified = match json_required_string(fields, "unified") {
    "stop" => @provider.V4FinishStop
    "length" => @provider.V4FinishLength
    "content-filter" => @provider.V4FinishContentFilter
    "tool-calls" => @provider.V4FinishToolCalls
    "error" => @provider.V4FinishError
    "other" => @provider.V4FinishOther
    other => raise harness_error("Unknown harness finish reason: " + other)
  }
  { unified, raw: json_optional_string(fields, "raw") }
}

///|
fn decode_harness_usage(
  value : Json?,
) -> @provider.LanguageModelV4Usage raise HarnessError {
  guard value is Some(Object(fields)) else {
    raise harness_error("Harness bridge usage must be an object")
  }
  let input = match fields.get("inputTokens") {
    Some(Object(token_fields)) => token_fields
    _ => Map([])
  }
  let output = match fields.get("outputTokens") {
    Some(Object(token_fields)) => token_fields
    _ => Map([])
  }
  {
    input_tokens: {
      total: json_optional_int(input, "total"),
      no_cache: json_optional_int(input, "noCache"),
      cache_read: json_optional_int(input, "cacheRead"),
      cache_write: json_optional_int(input, "cacheWrite"),
    },
    output_tokens: {
      total: json_optional_int(output, "total"),
      text: json_optional_int(output, "text"),
      reasoning: json_optional_int(output, "reasoning"),
    },
    raw: fields.get("raw"),
  }
}

///|
/// Consume bridge frames until the remote side closes or a terminal finish is
/// received. `on_event` is synchronous by design, mirroring the host callback
/// shape used by MoonBit's V4 language-model streaming contract.
pub async fn HarnessV1BridgeState::consume(
  self : HarnessV1BridgeState,
  on_event : (HarnessV1StreamPart) -> Unit,
) -> Unit raise HarnessError {
  guard !self.closed.val else {
    raise harness_error("Harness bridge connection is closed")
  }
  for ;; {
    let frame = self.connection.receive() catch {
      error =>
        raise HarnessError(
          message="Failed to receive harness bridge frame",
          cause=Some(@debug.to_string(error)),
        )
    }
    match frame {
      None => return
      Some(value) => {
        let frame = decode_harness_v1_bridge_outbound_frame(value)
        match frame {
          HarnessBridgeStreamPart(seq~, part~) => {
            on_event(part)
            self.record_delivered_seq(seq)
            if part is HarnessFinish(..) {
              return
            }
          }
          HarnessBridgeHello(state~, last_seq~) => {
            self.lifecycle_state_value.val = state
            if last_seq is Some(value) {
              self.bridge_last_seq.val = value
            }
          }
          HarnessBridgeDetached(data~) => {
            self.detach_data_value.val = Some(data)
            return
          }
          HarnessBridgeThread(thread_id~) =>
            self.thread_id_value.val = Some(thread_id)
          HarnessBridgeSandboxLog(seq~, source~, stream~, line~) => {
            self.report_diagnostic(HarnessV1Diagnostic::{
              level: if stream == "stderr" {
                HarnessDebugWarn
              } else {
                HarnessDebugInfo
              },
              message: line,
              subsystem: "sandbox.log." + source,
              kind: "log",
              source: Some(source),
              stream: Some(stream),
              attrs: None,
              error: None,
              session_id: self.session_id_value,
              timestamp: @env.now(),
            })
            self.record_delivered_seq(seq)
          }
          HarnessBridgeDebugEvent(
            seq~,
            level~,
            subsystem~,
            message~,
            attrs~,
            error~
          ) => {
            self.report_diagnostic(HarnessV1Diagnostic::{
              level,
              message,
              subsystem,
              kind: "event",
              source: None,
              stream: None,
              attrs,
              error,
              session_id: self.session_id_value,
              timestamp: @env.now(),
            })
            self.record_delivered_seq(seq)
          }
          HarnessBridgeReady(..) => ()
        }
      }
    }
  }
}

///|
fn HarnessV1BridgeState::record_delivered_seq(
  self : HarnessV1BridgeState,
  seq : Int?,
) -> Unit {
  if seq is Some(value) {
    if value > self.last_seen_event_id.val {
      self.last_seen_event_id.val = value
    }
    if value > self.bridge_last_seq.val {
      self.bridge_last_seq.val = value
    }
  }
}

///|
fn HarnessV1BridgeState::report_diagnostic(
  self : HarnessV1BridgeState,
  diagnostic : HarnessV1Diagnostic,
) -> Unit {
  if self.diagnostic_reporter is Some(report) {
    report(diagnostic)
  }
}

///|
/// Pi extended-thinking budget level.
pub(all) enum PiThinkingLevel {
  PiThinkingOff
  PiThinkingMinimal
  PiThinkingLow
  PiThinkingMedium
  PiThinkingHigh
  PiThinkingXHigh
} derive(Debug, Eq)

///|
/// Return the Pi wire spelling of a thinking level.
pub fn PiThinkingLevel::to_string(self : PiThinkingLevel) -> String {
  match self {
    PiThinkingOff => "off"
    PiThinkingMinimal => "minimal"
    PiThinkingLow => "low"
    PiThinkingMedium => "medium"
    PiThinkingHigh => "high"
    PiThinkingXHigh => "xhigh"
  }
}

///|
/// Pi adapter construction settings.
pub(all) struct PiHarnessSettings {
  auth : PiAuthOptions?
  model : String?
  thinking_level : PiThinkingLevel?
  agent_dir : String?
  transport : @harness.HarnessV1BridgeTransportConfig?
}

///|
/// Construct Pi adapter settings.
pub fn PiHarnessSettings::new(
  auth? : PiAuthOptions,
  model? : String,
  thinking_level? : PiThinkingLevel,
  agent_dir? : String,
  transport? : @harness.HarnessV1BridgeTransportConfig,
) -> PiHarnessSettings {
  { auth, model, thinking_level, agent_dir, transport }
}

///|
fn pi_schema(properties : Map[String, Json]) -> Json {
  ({ "type": "object", "properties": properties } : Json)
}

///|
fn pi_builtin_tools() -> Array[@harness.HarnessV1BuiltinTool] {
  [
    @harness.common_tool(
      common_name=@harness.HarnessRead,
      native_name="read",
      input_schema=pi_schema({ "file_path": { "type": "string" } }),
      description="Read file contents",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessWrite,
      native_name="write",
      input_schema=pi_schema({
        "file_path": { "type": "string" },
        "content": { "type": "string" },
      }),
      description="Overwrite or create a file",
      tool_use_kind=@harness.HarnessEditTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessEdit,
      native_name="edit",
      input_schema=pi_schema({
        "file_path": { "type": "string" },
        "old_string": { "type": "string" },
        "new_string": { "type": "string" },
      }),
      description="Edit a file by exact string replacement",
      tool_use_kind=@harness.HarnessEditTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessBash,
      native_name="bash",
      input_schema=pi_schema({ "command": { "type": "string" } }),
      description="Execute a shell command in the sandbox",
      tool_use_kind=@harness.HarnessBashTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessGrep,
      native_name="grep",
      input_schema=pi_schema({ "pattern": { "type": "string" } }),
      description="Search file contents with regex",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessGlob,
      native_name="find",
      input_schema=pi_schema({ "pattern": { "type": "string" } }),
      description="Find files matching a glob pattern",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
    @harness.native_harness_tool(
      native_name="ls",
      input_schema=pi_schema({ "path": { "type": "string" } }),
      description="List directory entries",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
  ]
}

///|
/// Pi Harness V1 adapter.
pub struct PiHarness {
  settings : PiHarnessSettings
}

///|
fn PiHarness::resolved_transport(
  self : PiHarness,
  options : @harness.HarnessV1StartOptions,
) -> @harness.HarnessV1BridgeTransportConfig raise @harness.HarnessError {
  if self.settings.transport is Some(value) {
    return value
  }
  guard @env.get_env_var("PI_BRIDGE_COMMAND") is Some(command) && command != "" else {
    raise @harness.HarnessError(
      message="Pi requires a configured MoonBit bridge transport or PI_BRIDGE_COMMAND",
      cause=None,
    )
  }
  @harness.HarnessV1BridgeTransportConfig::stdio(
    @harness.HarnessV1StdioConfig::new(
      command~,
      args=@env.get_env_var("PI_BRIDGE_ARGS")
        .map(value => [ for item in value.split(" ") => item.to_owned() ])
        .unwrap_or([]),
      env=resolve_pi_env(options?=self.settings.auth),
      cwd=options.session_work_dir,
    ),
  )
}

///|
pub impl @harness.HarnessV1 for PiHarness with fn specification_version(_self) {
  @harness.HARNESS_V1_SPECIFICATION_VERSION
}

///|
pub impl @harness.HarnessV1 for PiHarness with fn harness_id(_self) {
  "pi"
}

///|
pub impl @harness.HarnessV1 for PiHarness with fn builtin_tools(_self) {
  pi_builtin_tools()
}

///|
pub impl @harness.HarnessV1 for PiHarness with fn supports_builtin_tool_approvals(
  _self,
) {
  true
}

///|
pub impl @harness.HarnessV1 for PiHarness with fn supports_builtin_tool_filtering(
  _self,
) {
  true
}

///|
pub impl @harness.HarnessV1 for PiHarness with fn get_bootstrap(_self) {
  None
}

///|
pub impl @harness.HarnessV1 for PiHarness with fn do_start(self, options) {
  @provider.check_cancellation(options.cancellation_token)
  if options.resume_from is Some(state) {
    @harness.validate_harness_v1_lifecycle_state(
      "pi",
      state.harness_id,
      state.specification_version,
    )
  }
  if options.continue_from is Some(state) {
    @harness.validate_harness_v1_lifecycle_state(
      "pi",
      state.harness_id,
      state.specification_version,
    )
  }
  let lifecycle = options.lifecycle_state()
  let transport = self.resolved_transport(options)
  let connection = transport.connect(options)
  let last_seen_event_id = lifecycle
    .map(@harness.harness_v1_lifecycle_last_seen_event_id)
    .unwrap_or(0)
  if lifecycle is Some(_) && last_seen_event_id > 0 {
    @harness.send_harness_v1_bridge_command(
      connection,
      @harness.HarnessBridgeResume(last_seen_event_id~),
    )
  }
  let extension : Map[String, Json] = Map([])
  if self.settings.thinking_level is Some(value) {
    extension["thinkingLevel"] = Json::string(value.to_string())
  }
  if self.settings.agent_dir is Some(value) {
    extension["agentDir"] = Json::string(value)
  }
  let model = resolve_pi_model(self.settings.model)
  let session = @harness.HarnessV1BridgeSession::new(
    session_id=options.session_id,
    harness_id="pi",
    connection~,
    model_id?=model,
    resumed=lifecycle is Some(_),
    last_seen_event_id~,
    extension~,
    permission_mode?=options.permission_mode,
    tool_filtering?=options.builtin_tool_filtering,
    diagnostic_reporter?=@harness.harness_v1_diagnostic_reporter(
      options.observability,
    ),
  )
  session as &@harness.HarnessV1Session
}

///|
/// Create a Pi Harness V1 adapter.
pub fn createPi(
  settings? : PiHarnessSettings = PiHarnessSettings::new(),
) -> PiHarness {
  { settings, }
}

///|
/// Snake-case alias for `createPi`.
pub fn create_pi(
  settings? : PiHarnessSettings = PiHarnessSettings::new(),
) -> PiHarness {
  createPi(settings~)
}

///|
/// Default Pi adapter instance.
pub let pi : PiHarness = createPi()

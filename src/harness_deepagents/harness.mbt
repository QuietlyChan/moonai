///|
/// DeepAgents adapter construction settings.
pub(all) struct DeepAgentsHarnessSettings {
  auth : DeepAgentsAuthOptions?
  model : String?
  port : Int?
  startup_timeout_ms : Int
  recursion_limit : Int?
  transport : @harness.HarnessV1BridgeTransportConfig?
}

///|
/// Construct DeepAgents adapter settings.
pub fn DeepAgentsHarnessSettings::new(
  auth? : DeepAgentsAuthOptions,
  model? : String,
  port? : Int,
  startup_timeout_ms? : Int = 120_000,
  recursion_limit? : Int,
  transport? : @harness.HarnessV1BridgeTransportConfig,
) -> DeepAgentsHarnessSettings {
  { auth, model, port, startup_timeout_ms, recursion_limit, transport }
}

///|
fn deep_agents_schema(properties : Map[String, Json]) -> Json {
  ({ "type": "object", "properties": properties } : Json)
}

///|
fn deep_agents_builtin_tools() -> Array[@harness.HarnessV1BuiltinTool] {
  [
    @harness.common_tool(
      common_name=@harness.HarnessRead,
      native_name="read_file",
      input_schema=deep_agents_schema({ "file_path": { "type": "string" } }),
      description="Read file contents",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessWrite,
      native_name="write_file",
      input_schema=deep_agents_schema({
        "file_path": { "type": "string" },
        "content": { "type": "string" },
      }),
      description="Create a file",
      tool_use_kind=@harness.HarnessEditTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessEdit,
      native_name="edit_file",
      input_schema=deep_agents_schema({
        "file_path": { "type": "string" },
        "old_string": { "type": "string" },
        "new_string": { "type": "string" },
      }),
      description="Perform exact string replacements in a file",
      tool_use_kind=@harness.HarnessEditTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessBash,
      native_name="execute",
      input_schema=deep_agents_schema({ "command": { "type": "string" } }),
      description="Run a shell command",
      tool_use_kind=@harness.HarnessBashTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessGrep,
      native_name="grep",
      input_schema=deep_agents_schema({ "pattern": { "type": "string" } }),
      description="Search file contents",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessGlob,
      native_name="glob",
      input_schema=deep_agents_schema({ "pattern": { "type": "string" } }),
      description="Find files matching a glob pattern",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
  ]
}

///|
/// DeepAgents Harness V1 adapter.
pub struct DeepAgentsHarness {
  settings : DeepAgentsHarnessSettings
}

///|
async fn DeepAgentsHarness::resolved_transport(
  self : DeepAgentsHarness,
  options : @harness.HarnessV1StartOptions,
) -> @harness.HarnessV1BridgeTransportConfig raise @harness.HarnessError {
  if self.settings.transport is Some(value) {
    return value
  }
  if @env.get_env_var("DEEPAGENTS_BRIDGE_COMMAND") is Some(command) &&
    command != "" {
    return @harness.HarnessV1BridgeTransportConfig::stdio(
      @harness.HarnessV1StdioConfig::new(
        command~,
        args=@env.get_env_var("DEEPAGENTS_BRIDGE_ARGS")
          .map(value => [ for item in value.split(" ") => item.to_owned() ])
          .unwrap_or([]),
        env=resolve_deep_agents_env(auth?=self.settings.auth),
        cwd=options.session_work_dir,
      ),
    )
  }
  let port = match self.settings.port {
    Some(value) => value
    None => options.sandbox_session.ports().get(0).unwrap_or(4096)
  }
  let url = options.sandbox_session.get_port_url(port~, protocol="ws") catch {
    error =>
      raise @harness.HarnessError(
        message="Failed to resolve DeepAgents bridge URL",
        cause=Some(@debug.to_string(error)),
      )
  }
  @harness.HarnessV1BridgeTransportConfig::websocket(url~)
}

///|
pub impl @harness.HarnessV1 for DeepAgentsHarness with fn specification_version(
  _self,
) {
  @harness.HARNESS_V1_SPECIFICATION_VERSION
}

///|
pub impl @harness.HarnessV1 for DeepAgentsHarness with fn harness_id(_self) {
  "deepagents"
}

///|
pub impl @harness.HarnessV1 for DeepAgentsHarness with fn builtin_tools(_self) {
  deep_agents_builtin_tools()
}

///|
pub impl @harness.HarnessV1 for DeepAgentsHarness with fn supports_builtin_tool_approvals(
  _self,
) {
  true
}

///|
pub impl @harness.HarnessV1 for DeepAgentsHarness with fn supports_builtin_tool_filtering(
  _self,
) {
  true
}

///|
pub impl @harness.HarnessV1 for DeepAgentsHarness with fn get_bootstrap(_self) {
  None
}

///|
pub impl @harness.HarnessV1 for DeepAgentsHarness with fn do_start(
  self,
  options,
) {
  @provider.check_cancellation(options.cancellation_token)
  if options.resume_from is Some(state) {
    @harness.validate_harness_v1_lifecycle_state(
      "deepagents",
      state.harness_id,
      state.specification_version,
    )
  }
  if options.continue_from is Some(state) {
    @harness.validate_harness_v1_lifecycle_state(
      "deepagents",
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
  if self.settings.recursion_limit is Some(value) {
    extension["recursionLimit"] = Json::number(value.to_double())
  }
  let session = @harness.HarnessV1BridgeSession::new(
    session_id=options.session_id,
    harness_id="deepagents",
    connection~,
    model_id?=self.settings.model,
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
/// Create a DeepAgents Harness V1 adapter.
pub fn createDeepAgents(
  settings? : DeepAgentsHarnessSettings = DeepAgentsHarnessSettings::new(),
) -> DeepAgentsHarness {
  { settings, }
}

///|
/// Snake-case alias for `createDeepAgents`.
pub fn create_deep_agents(
  settings? : DeepAgentsHarnessSettings = DeepAgentsHarnessSettings::new(),
) -> DeepAgentsHarness {
  createDeepAgents(settings~)
}

///|
/// Default DeepAgents adapter instance.
pub let deepAgents : DeepAgentsHarness = createDeepAgents()

///|
/// Snake-case alias for the default DeepAgents adapter.
pub let deep_agents : DeepAgentsHarness = deepAgents

///|
/// OpenCode adapter construction settings.
pub(all) struct OpenCodeHarnessSettings {
  auth : OpenCodeAuthOptions?
  model : String?
  provider : String?
  reasoning_variant : String?
  port : Int?
  startup_timeout_ms : Int
  transport : @harness.HarnessV1BridgeTransportConfig?
}

///|
/// Construct OpenCode adapter settings.
pub fn OpenCodeHarnessSettings::new(
  auth? : OpenCodeAuthOptions,
  model? : String,
  provider? : String,
  reasoning_variant? : String,
  port? : Int,
  startup_timeout_ms? : Int = 120_000,
  transport? : @harness.HarnessV1BridgeTransportConfig,
) -> OpenCodeHarnessSettings {
  {
    auth,
    model,
    provider,
    reasoning_variant,
    port,
    startup_timeout_ms,
    transport,
  }
}

///|
fn open_code_schema(properties : Map[String, Json]) -> Json {
  ({ "type": "object", "properties": properties } : Json)
}

///|
fn open_code_builtin_tools() -> Array[@harness.HarnessV1BuiltinTool] {
  [
    @harness.common_tool(
      common_name=@harness.HarnessRead,
      native_name="view",
      input_schema=open_code_schema({ "path": { "type": "string" } }),
      description="Read file contents",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessWrite,
      native_name="write",
      input_schema=open_code_schema({
        "path": { "type": "string" },
        "content": { "type": "string" },
      }),
      description="Write content to a file",
      tool_use_kind=@harness.HarnessEditTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessEdit,
      native_name="edit",
      input_schema=open_code_schema({
        "path": { "type": "string" },
        "old_string": { "type": "string" },
        "new_string": { "type": "string" },
      }),
      description="Edit a file by replacing text",
      tool_use_kind=@harness.HarnessEditTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessBash,
      native_name="bash",
      input_schema=open_code_schema({ "command": { "type": "string" } }),
      description="Execute a shell command",
      tool_use_kind=@harness.HarnessBashTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessGlob,
      native_name="glob",
      input_schema=open_code_schema({ "pattern": { "type": "string" } }),
      description="Find files matching a glob pattern",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
    @harness.common_tool(
      common_name=@harness.HarnessGrep,
      native_name="grep",
      input_schema=open_code_schema({ "pattern": { "type": "string" } }),
      description="Search file contents with regex",
      tool_use_kind=@harness.HarnessReadonlyTool,
    ),
  ]
}

///|
/// OpenCode Harness V1 adapter.
pub struct OpenCodeHarness {
  settings : OpenCodeHarnessSettings
}

///|
async fn OpenCodeHarness::resolved_transport(
  self : OpenCodeHarness,
  options : @harness.HarnessV1StartOptions,
) -> @harness.HarnessV1BridgeTransportConfig raise @harness.HarnessError {
  if self.settings.transport is Some(value) {
    return value
  }
  if @env.get_env_var("OPENCODE_BRIDGE_COMMAND") is Some(command) &&
    command != "" {
    return @harness.HarnessV1BridgeTransportConfig::stdio(
      @harness.HarnessV1StdioConfig::new(
        command~,
        args=@env.get_env_var("OPENCODE_BRIDGE_ARGS")
          .map(value => [ for item in value.split(" ") => item.to_owned() ])
          .unwrap_or([]),
        env=resolve_open_code_env(
          auth?=self.settings.auth,
          model?=self.settings.model,
          provider?=self.settings.provider,
        ),
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
        message="Failed to resolve OpenCode bridge URL",
        cause=Some(@debug.to_string(error)),
      )
  }
  @harness.HarnessV1BridgeTransportConfig::websocket(url~)
}

///|
pub impl @harness.HarnessV1 for OpenCodeHarness with fn specification_version(
  _self,
) {
  @harness.HARNESS_V1_SPECIFICATION_VERSION
}

///|
pub impl @harness.HarnessV1 for OpenCodeHarness with fn harness_id(_self) {
  "opencode"
}

///|
pub impl @harness.HarnessV1 for OpenCodeHarness with fn builtin_tools(_self) {
  open_code_builtin_tools()
}

///|
pub impl @harness.HarnessV1 for OpenCodeHarness with fn supports_builtin_tool_approvals(
  _self,
) {
  true
}

///|
pub impl @harness.HarnessV1 for OpenCodeHarness with fn supports_builtin_tool_filtering(
  _self,
) {
  false
}

///|
pub impl @harness.HarnessV1 for OpenCodeHarness with fn get_bootstrap(_self) {
  None
}

///|
pub impl @harness.HarnessV1 for OpenCodeHarness with fn do_start(self, options) {
  @provider.check_cancellation(options.cancellation_token)
  if options.resume_from is Some(state) {
    @harness.validate_harness_v1_lifecycle_state(
      "opencode",
      state.harness_id,
      state.specification_version,
    )
  }
  if options.continue_from is Some(state) {
    @harness.validate_harness_v1_lifecycle_state(
      "opencode",
      state.harness_id,
      state.specification_version,
    )
  }
  let transport = self.resolved_transport(options)
  let connection = transport.connect(options)
  let lifecycle = options.lifecycle_state()
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
  let coordinate = split_open_code_model(
    self.settings.model,
    self.settings.provider,
  )
  if coordinate.provider_id is Some(value) {
    extension["providerId"] = Json::string(value)
  }
  if coordinate.model_id is Some(value) {
    extension["modelId"] = Json::string(value)
  }
  if self.settings.reasoning_variant is Some(value) {
    extension["reasoningVariant"] = Json::string(value)
  }
  let session = @harness.HarnessV1BridgeSession::new(
    session_id=options.session_id,
    harness_id="opencode",
    connection~,
    model_id?=coordinate.model,
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
/// Create an OpenCode Harness V1 adapter.
pub fn createOpenCode(
  settings? : OpenCodeHarnessSettings = OpenCodeHarnessSettings::new(),
) -> OpenCodeHarness {
  { settings, }
}

///|
/// Snake-case alias for `createOpenCode`.
pub fn create_open_code(
  settings? : OpenCodeHarnessSettings = OpenCodeHarnessSettings::new(),
) -> OpenCodeHarness {
  createOpenCode(settings~)
}

///|
/// Default OpenCode adapter instance.
pub let openCode : OpenCodeHarness = createOpenCode()

///|
/// Snake-case alias for the default OpenCode adapter.
pub let open_code : OpenCodeHarness = openCode

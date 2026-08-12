///|
/// Transport configuration shared by bridge-backed harness adapters.
pub(all) enum HarnessV1BridgeTransportConfig {
  HarnessBridgeWebSocket(
    url~ : String,
    token~ : String?,
    headers~ : Map[String, String]
  )
  HarnessBridgeStdio(HarnessV1StdioConfig)
  HarnessBridgeConnectionFactory(
    async (HarnessV1StartOptions) -> &HarnessV1BridgeConnection
  )
}

///|
/// Construct a WebSocket bridge transport configuration.
pub fn HarnessV1BridgeTransportConfig::websocket(
  url~ : String,
  token? : String,
  headers? : Map[String, String] = Map([]),
) -> HarnessV1BridgeTransportConfig {
  HarnessBridgeWebSocket(url~, token~, headers~)
}

///|
/// Construct a persistent stdio NDJSON bridge transport configuration.
pub fn HarnessV1BridgeTransportConfig::stdio(
  config : HarnessV1StdioConfig,
) -> HarnessV1BridgeTransportConfig {
  HarnessBridgeStdio(config)
}

///|
/// Construct an injectable bridge transport for hosts and deterministic tests.
pub fn HarnessV1BridgeTransportConfig::custom(
  connect : async (HarnessV1StartOptions) -> &HarnessV1BridgeConnection,
) -> HarnessV1BridgeTransportConfig {
  HarnessBridgeConnectionFactory(connect)
}

///|
/// Connect using a bridge transport configuration.
pub async fn HarnessV1BridgeTransportConfig::connect(
  self : HarnessV1BridgeTransportConfig,
  options : HarnessV1StartOptions,
) -> &HarnessV1BridgeConnection raise HarnessError {
  match self {
    HarnessBridgeWebSocket(url~, token~, headers~) =>
      connect_harness_v1_websocket(url, token?, headers~) catch {
        error =>
          raise HarnessError(
            message="Failed to connect harness WebSocket bridge",
            cause=Some(@debug.to_string(error)),
          )
      }
    HarnessBridgeStdio(config) => connect_harness_v1_stdio(config)
    HarnessBridgeConnectionFactory(connect) =>
      connect(options) catch {
        error =>
          raise HarnessError(
            message="Failed to connect custom harness bridge",
            cause=Some(@debug.to_string(error)),
          )
      }
  }
}

///|
/// Resolve the diagnostics callback from optional observability settings.
pub fn harness_v1_diagnostic_reporter(
  observability : HarnessV1Observability?,
) -> HarnessV1DiagnosticReporter? {
  match observability {
    Some(value) => Some(value.report)
    None => None
  }
}

///|
/// Read an integer bridge cursor from lifecycle state data.
pub fn harness_v1_lifecycle_last_seen_event_id(data : Json) -> Int {
  guard data is Object(fields) else { return 0 }
  match fields.get("lastSeenEventId") {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
/// Return the active lifecycle state from start options.
pub fn HarnessV1StartOptions::lifecycle_state(
  self : HarnessV1StartOptions,
) -> Json? {
  match self.continue_from {
    Some(value) => Some(value.data)
    None => self.resume_from.map(value => value.data)
  }
}

///|
/// Copy non-empty environment values from a map.
pub fn compact_harness_env(values : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for key, value in values {
    if value != "" {
      result[key] = value
    }
  }
  result
}

///|
/// Resolve ambient AI Gateway credentials used by all harness adapters.
pub fn harness_ai_gateway_env(
  environment? : Map[String, String] = @env.get_env_vars(),
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  let api_key = match environment.get("AI_GATEWAY_API_KEY") {
    Some(value) => Some(value)
    None => environment.get("VERCEL_OIDC_TOKEN")
  }
  if api_key is Some(value) && value != "" {
    result["AI_GATEWAY_API_KEY"] = value
  }
  result["AI_GATEWAY_BASE_URL"] = environment
    .get("AI_GATEWAY_BASE_URL")
    .unwrap_or("https://ai-gateway.vercel.sh")
  result
}

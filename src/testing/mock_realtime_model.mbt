///|
/// Deterministic realtime model for SDK consumer and session tests.
pub struct MockRealtimeModel {
  priv provider_name : String
  priv model_id : String
  priv client_secret : @provider.RealtimeClientSecretResult
  priv websocket_config : @provider.RealtimeWebSocketConfig
  priv parsed_events : Array[@provider.RealtimeServerEvent]
}

///|
/// Construct a deterministic realtime model.
pub fn MockRealtimeModel::new(
  provider_name? : String = "mock",
  model_id? : String = "mock-realtime-model",
  client_secret? : @provider.RealtimeClientSecretResult,
  websocket_config? : @provider.RealtimeWebSocketConfig,
  parsed_events? : Array[@provider.RealtimeServerEvent] = [],
) -> MockRealtimeModel {
  {
    provider_name,
    model_id,
    client_secret: client_secret.unwrap_or(
      @provider.RealtimeClientSecretResult::new(token="mock-token", url=""),
    ),
    websocket_config: websocket_config.unwrap_or(
      @provider.RealtimeWebSocketConfig::new(url=""),
    ),
    parsed_events,
  }
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn do_create_client_secret(
  self,
  _options,
) {
  self.client_secret
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn get_websocket_config(
  self,
  _token,
  _url,
) {
  self.websocket_config
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn parse_server_event(
  self,
  _event,
) {
  self.parsed_events.copy()
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn serialize_client_event(
  _self,
  _event,
) {
  ({ "type": "mock" } : Json)
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn build_session_config(
  _self,
  _config,
) {
  ({ "type": "mock" } : Json)
}

///|
pub impl @provider.RealtimeModelV4 for MockRealtimeModel with fn get_health_check_response(
  _self,
  _raw,
) {
  None
}

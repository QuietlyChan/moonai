///|
/// V4 names for the provider-neutral realtime value types.
///
/// The value representation is shared with the existing WebSocket adapter
/// boundary. Keeping aliases here avoids duplicating a large event union while
/// giving callers a versioned contract namespace.
/// V4 alias for the modalities returned by a realtime model.
pub type RealtimeModelV4OutputModality = RealtimeOutputModality

///|
/// V4 alias for input-audio transcription settings.
pub type RealtimeModelV4AudioTranscriptionConfig = RealtimeAudioTranscriptionConfig

///|
/// V4 alias for server-side turn detection settings.
pub type RealtimeModelV4TurnDetection = RealtimeTurnDetection

///|
/// V4 alias for a realtime tool definition.
pub type RealtimeModelV4ToolDefinition = RealtimeToolDefinition

///|
/// V4 alias for a realtime session configuration.
pub type RealtimeModelV4SessionConfig = RealtimeSessionConfig

///|
/// V4 alias for a conversation item sent to a realtime session.
pub type RealtimeModelV4ConversationItem = RealtimeConversationItem

///|
/// V4 alias for response-creation options.
pub type RealtimeModelV4ResponseCreateOptions = RealtimeResponseCreateOptions

///|
/// V4 alias for a client event.
pub type RealtimeModelV4ClientEvent = RealtimeClientEvent

///|
/// V4 alias for a server event.
pub type RealtimeModelV4ServerEvent = RealtimeServerEvent

///|
/// V4 alias for client-secret request options.
pub type RealtimeModelV4ClientSecretOptions = RealtimeClientSecretOptions

///|
/// V4 alias for the client-secret result.
pub type RealtimeModelV4ClientSecretResult = RealtimeClientSecretResult

///|
/// V4 alias for WebSocket connection settings.
pub type RealtimeModelV4WebSocketConfig = RealtimeWebSocketConfig

///|
/// V4 options for a provider-level realtime token request.
///
/// The `model` field selects the model used to mint the short-lived client
/// secret; the remaining fields are shared with the model-level request.
pub type RealtimeFactoryV4GetTokenOptions = RealtimeFactoryTokenOptions

///|
/// Versioned realtime model contract corresponding to AI SDK's
/// `RealtimeModelV4`.
///
/// MoonBit represents provider callbacks with ordinary functions and returns
/// an array from `parse_server_event` so one wire message can expand into more
/// than one normalized event. The rest of the lifecycle is intentionally
/// provider-neutral; WebSocket session ownership remains above this SPI.
pub(open) trait RealtimeModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn do_create_client_secret(Self, RealtimeModelV4ClientSecretOptions) -> RealtimeModelV4ClientSecretResult
  fn get_websocket_config(Self, String, String) -> RealtimeModelV4WebSocketConfig
  fn parse_server_event(Self, Json) -> Array[RealtimeModelV4ServerEvent]
  fn serialize_client_event(Self, RealtimeModelV4ClientEvent) -> Json
  fn build_session_config(Self, RealtimeModelV4SessionConfig) -> Json
  fn get_health_check_response(Self, Json) -> Json?
}

///|
/// Versioned provider-level realtime factory contract.
///
/// A factory is separate from a model because AI SDK exposes token creation at
/// the provider level while model identity is selected lazily.
pub(open) trait RealtimeFactoryV4 {
  fn provider(Self) -> String
  fn model(Self, String) -> &RealtimeModelV4
  async fn get_token(Self, RealtimeFactoryV4GetTokenOptions) -> RealtimeModelV4ClientSecretResult
}

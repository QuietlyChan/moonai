///|
/// Request a short-lived secret through a provider-neutral realtime model.
pub async fn create_realtime_client_secret(
  model : &RealtimeModelV4,
  options? : RealtimeClientSecretOptions = RealtimeClientSecretOptions::new(),
) -> RealtimeClientSecretResult {
  model.do_create_client_secret(options)
}

///|
/// Camel-case alias for AI SDK-style consumers.
pub async fn createRealtimeClientSecret(
  model : &RealtimeModelV4,
  options? : RealtimeClientSecretOptions = RealtimeClientSecretOptions::new(),
) -> RealtimeClientSecretResult {
  create_realtime_client_secret(model, options~)
}

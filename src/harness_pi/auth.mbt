///|
/// Authentication options for the Pi adapter.
pub(all) enum PiAuthOptions {
  PiGatewayAuth(api_key~ : String?, base_url~ : String?)
  PiCustomEnv(Map[String, String])
} derive(Debug, Eq)

///|
/// Resolve environment variables passed to the Pi bridge or CLI runtime.
pub fn resolve_pi_env(
  options? : PiAuthOptions,
  environment? : Map[String, String] = @env.get_env_vars(),
) -> Map[String, String] {
  match options {
    Some(PiCustomEnv(values)) => @harness.compact_harness_env(values)
    Some(PiGatewayAuth(api_key~, base_url~)) => {
      let ambient = @harness.harness_ai_gateway_env(environment~)
      @harness.compact_harness_env({
        "AI_GATEWAY_API_KEY": api_key.unwrap_or(
          ambient.get("AI_GATEWAY_API_KEY").unwrap_or(""),
        ),
        "AI_GATEWAY_BASE_URL": base_url.unwrap_or(
          ambient
          .get("AI_GATEWAY_BASE_URL")
          .unwrap_or("https://ai-gateway.vercel.sh"),
        ),
      })
    }
    None => @harness.harness_ai_gateway_env(environment~)
  }
}

///|
/// AI SDK-style spelling for `resolve_pi_env`.
pub fn resolvePiEnv(
  options? : PiAuthOptions,
  environment? : Map[String, String] = @env.get_env_vars(),
) -> Map[String, String] {
  resolve_pi_env(options?, environment~)
}

///|
/// Resolve Pi's effective model id.
pub fn resolve_pi_model(
  model : String?,
  environment? : Map[String, String] = @env.get_env_vars(),
) -> String? {
  match model {
    Some(value) => Some(value)
    None => {
      let gateway = @harness.harness_ai_gateway_env(environment~)
      if gateway.get("AI_GATEWAY_API_KEY") is Some(value) && value != "" {
        Some(DEFAULT_PI_GATEWAY_MODEL_ID)
      } else {
        None
      }
    }
  }
}

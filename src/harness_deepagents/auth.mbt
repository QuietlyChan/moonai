///|
/// Authentication options for the DeepAgents adapter.
pub(all) enum DeepAgentsAuthOptions {
  DeepAgentsAnthropicAuth(
    api_key~ : String?,
    auth_token~ : String?,
    base_url~ : String?
  )
  DeepAgentsGatewayAuth(api_key~ : String?, base_url~ : String?)
} derive(Debug, Eq)

///|
/// Resolve environment variables passed to the DeepAgents bridge.
pub fn resolve_deep_agents_env(
  auth? : DeepAgentsAuthOptions,
  environment? : Map[String, String] = @env.get_env_vars(),
) -> Map[String, String] {
  match auth {
    Some(DeepAgentsAnthropicAuth(api_key~, auth_token~, base_url~)) =>
      @harness.compact_harness_env({
        "ANTHROPIC_API_KEY": api_key.unwrap_or(
          environment.get("ANTHROPIC_API_KEY").unwrap_or(""),
        ),
        "ANTHROPIC_AUTH_TOKEN": auth_token.unwrap_or(
          environment.get("ANTHROPIC_AUTH_TOKEN").unwrap_or(""),
        ),
        "ANTHROPIC_BASE_URL": base_url.unwrap_or(
          environment.get("ANTHROPIC_BASE_URL").unwrap_or(""),
        ),
      })
    Some(DeepAgentsGatewayAuth(api_key~, base_url~)) => {
      let gateway = @harness.harness_ai_gateway_env(environment~)
      let key = api_key.unwrap_or(
        gateway.get("AI_GATEWAY_API_KEY").unwrap_or(""),
      )
      @harness.compact_harness_env({
        "AI_GATEWAY_API_KEY": key,
        "ANTHROPIC_API_KEY": key,
        "ANTHROPIC_BASE_URL": base_url
        .unwrap_or(
          gateway
          .get("AI_GATEWAY_BASE_URL")
          .unwrap_or("https://ai-gateway.vercel.sh"),
        )
        .trim_end(chars="/")
        .to_owned(),
      })
    }
    None => {
      let gateway = @harness.harness_ai_gateway_env(environment~)
      if gateway.get("AI_GATEWAY_API_KEY") is Some(value) && value != "" {
        resolve_deep_agents_env(
          auth=DeepAgentsGatewayAuth(api_key=None, base_url=None),
          environment~,
        )
      } else {
        resolve_deep_agents_env(
          auth=DeepAgentsAnthropicAuth(
            api_key=None,
            auth_token=None,
            base_url=None,
          ),
          environment~,
        )
      }
    }
  }
}

///|
/// AI SDK-style spelling for `resolve_deep_agents_env`.
pub fn resolveDeepAgentsEnv(
  auth? : DeepAgentsAuthOptions,
  environment? : Map[String, String] = @env.get_env_vars(),
) -> Map[String, String] {
  resolve_deep_agents_env(auth?, environment~)
}

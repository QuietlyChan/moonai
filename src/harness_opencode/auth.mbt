///|
/// Explicit authentication source used by the OpenCode adapter.
pub(all) enum OpenCodeAuthOptions {
  OpenCodeGatewayAuth(api_key~ : String?, base_url~ : String?)
  OpenCodeAnthropicAuth(
    api_key~ : String?,
    auth_token~ : String?,
    base_url~ : String?
  )
  OpenCodeOpenAIAuth(
    api_key~ : String?,
    base_url~ : String?,
    organization~ : String?,
    project~ : String?
  )
  OpenCodeCompatibleAuth(
    api_key~ : String?,
    base_url~ : String?,
    name~ : String?,
    query_params~ : Map[String, String]
  )
} derive(Debug, Eq)

///|
/// OpenCode's split provider/model coordinate.
pub(all) struct OpenCodeModelCoordinate {
  provider_id : String?
  model_id : String?
  model : String?
} derive(Debug, Eq)

///|
/// Infer the provider family used for ambient credentials.
pub fn resolve_open_code_provider(
  model : String?,
  provider : String?,
) -> String {
  match provider {
    Some("anthropic") => "anthropic"
    Some("openai") => "openai"
    _ =>
      match model {
        Some(value) if value.has_prefix("openai/") => "openai"
        Some(value) if value.has_prefix("anthropic/") => "anthropic"
        _ => "anthropic"
      }
  }
}

///|
/// Split an OpenCode model id into provider and model components.
pub fn split_open_code_model(
  model : String?,
  provider : String?,
) -> OpenCodeModelCoordinate {
  match model {
    None => { provider_id: None, model_id: None, model: None }
    Some(value) =>
      match value.find("/") {
        Some(index) =>
          {
            provider_id: Some(value[:index].to_owned()),
            model_id: Some(value[index + 1:].to_owned()),
            model: Some(value),
          }
        None =>
          {
            provider_id: provider,
            model_id: Some(value),
            model: Some(
              match provider {
                Some(prefix) => prefix + "/" + value
                None => value
              },
            ),
          }
      }
  }
}

///|
/// AI SDK-style spelling for `split_open_code_model`.
pub fn splitOpenCodeModel(
  model : String?,
  provider : String?,
) -> OpenCodeModelCoordinate {
  split_open_code_model(model, provider)
}

///|
/// Normalize AI Gateway's base URL for OpenCode.
pub fn to_open_code_gateway_base_url(base_url : String) -> String {
  let trimmed = base_url.trim_end(chars="/").to_owned()
  if trimmed.has_suffix("/v1") {
    trimmed
  } else {
    trimmed + "/v1"
  }
}

///|
/// AI SDK-style spelling for `to_open_code_gateway_base_url`.
pub fn toOpenCodeGatewayBaseUrl(base_url : String) -> String {
  to_open_code_gateway_base_url(base_url)
}

///|
/// Resolve the exact environment passed to the OpenCode bridge.
pub fn resolve_open_code_env(
  auth? : OpenCodeAuthOptions,
  model? : String,
  provider? : String,
  environment? : Map[String, String] = @env.get_env_vars(),
) -> Map[String, String] {
  match auth {
    Some(OpenCodeCompatibleAuth(api_key~, base_url~, name~, query_params~)) => {
      let values : Map[String, String] = Map([])
      values["OPENAI_API_KEY"] = api_key.unwrap_or(
        environment.get("OPENAI_API_KEY").unwrap_or(""),
      )
      values["OPENAI_BASE_URL"] = base_url.unwrap_or(
        environment.get("OPENAI_BASE_URL").unwrap_or(""),
      )
      values["OPENAI_NAME"] = name.unwrap_or(
        environment.get("OPENAI_NAME").unwrap_or(""),
      )
      if query_params.length() > 0 {
        let json : Map[String, Json] = Map([])
        for key, value in query_params {
          json[key] = Json::string(value)
        }
        values["OPENAI_QUERY_PARAMS_JSON"] = Json::object(json).stringify()
      } else {
        values["OPENAI_QUERY_PARAMS_JSON"] = environment
          .get("OPENAI_QUERY_PARAMS_JSON")
          .unwrap_or("")
      }
      @harness.compact_harness_env(values)
    }
    Some(OpenCodeOpenAIAuth(api_key~, base_url~, organization~, project~)) =>
      @harness.compact_harness_env({
        "OPENAI_API_KEY": api_key.unwrap_or(
          environment.get("OPENAI_API_KEY").unwrap_or(""),
        ),
        "OPENAI_BASE_URL": base_url.unwrap_or(
          environment.get("OPENAI_BASE_URL").unwrap_or(""),
        ),
        "OPENAI_ORGANIZATION": organization.unwrap_or(
          environment.get("OPENAI_ORGANIZATION").unwrap_or(""),
        ),
        "OPENAI_PROJECT": project.unwrap_or(
          environment.get("OPENAI_PROJECT").unwrap_or(""),
        ),
      })
    Some(OpenCodeAnthropicAuth(api_key~, auth_token~, base_url~)) =>
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
    Some(OpenCodeGatewayAuth(api_key~, base_url~)) =>
      @harness.compact_harness_env({
        "AI_GATEWAY_API_KEY": api_key.unwrap_or(
          @harness.harness_ai_gateway_env(environment~)
          .get("AI_GATEWAY_API_KEY")
          .unwrap_or(""),
        ),
        "AI_GATEWAY_BASE_URL": to_open_code_gateway_base_url(
          base_url.unwrap_or(
            @harness.harness_ai_gateway_env(environment~)
            .get("AI_GATEWAY_BASE_URL")
            .unwrap_or("https://ai-gateway.vercel.sh"),
          ),
        ),
      })
    None => {
      let gateway = @harness.harness_ai_gateway_env(environment~)
      if gateway.get("AI_GATEWAY_API_KEY") is Some(value) && value != "" {
        gateway["AI_GATEWAY_BASE_URL"] = to_open_code_gateway_base_url(
          gateway["AI_GATEWAY_BASE_URL"],
        )
        return gateway
      }
      if resolve_open_code_provider(model, provider) == "openai" {
        resolve_open_code_env(
          auth=OpenCodeOpenAIAuth(
            api_key=None,
            base_url=None,
            organization=None,
            project=None,
          ),
          model?,
          provider?,
          environment~,
        )
      } else {
        resolve_open_code_env(
          auth=OpenCodeAnthropicAuth(
            api_key=None,
            auth_token=None,
            base_url=None,
          ),
          model?,
          provider?,
          environment~,
        )
      }
    }
  }
}

///|
/// AI SDK-style spelling for `resolve_open_code_env`.
pub fn resolveOpenCodeEnv(
  auth? : OpenCodeAuthOptions,
  model? : String,
  provider? : String,
  environment? : Map[String, String] = @env.get_env_vars(),
) -> Map[String, String] {
  resolve_open_code_env(auth?, model?, provider?, environment~)
}

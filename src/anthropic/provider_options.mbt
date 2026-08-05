///|
priv struct AnthropicOptions {
  send_reasoning : Bool
  structured_output_mode : String
  thinking : AnthropicThinking?
  disable_parallel_tool_use : Bool?
  cache_control : Json?
  metadata_user_id : String?
  mcp_servers : Array[Json]
  container : Json?
  tool_streaming : Bool
  effort : String?
  task_budget : Json?
  speed : String?
  inference_geo : String?
  fallbacks : Json?
  beta_features : Array[String]
  context_management : Json?
}

///|
priv struct ParsedAnthropicOptions {
  options : AnthropicOptions
  warnings : Array[@provider.Warning]
}

///|
priv struct AnthropicPreparedRequest {
  body : Json
  warnings : Array[@provider.Warning]
  beta_features : Array[String]
  tool_name_mapping : @provider_utils.ToolNameMapping
}

///|
fn anthropic_reserved_fields() -> Array[String] {
  [
    "model", "messages", "max_tokens", "stream", "system", "temperature", "top_p",
    "stop_sequences", "tools", "tool_choice", "output_config",
  ]
}

///|
fn resolve_anthropic_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> @provider_utils.ProviderOptionsResolution {
  let canonical = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="anthropic.messages",
    reserved_fields=anthropic_reserved_fields(),
  )
  let custom = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name~,
    reserved_fields=anthropic_reserved_fields(),
  )
  if canonical.namespace_key is Some(key) && custom.namespace_key == Some(key) {
    return custom
  }
  if canonical.namespace_key is Some(_) || custom.namespace_key is Some(_) {
    return @provider_utils.merge_provider_options_resolutions(canonical, custom)
  }
  @provider_utils.resolve_provider_options(
    provider_options,
    provider_name~,
    aliases=["anthropic"],
    reserved_fields=anthropic_reserved_fields(),
  )
}

///|
fn invalid_anthropic_option(
  reader : @provider_utils.ProviderOptionsReader,
  feature : String,
  details : String,
) -> Unit {
  reader.add_warning(
    @provider.Warning::Compatibility(
      feature="providerOptions.\{feature}",
      details~,
    ),
  )
}

///|
fn parse_anthropic_thinking(
  reader : @provider_utils.ProviderOptionsReader,
) -> AnthropicThinking? {
  guard reader.take_object("thinking") is Some(value) else { return None }
  let json = Json::object(value)
  let kind = @provider_utils.json_string_field(json, "type").unwrap_or("")
  match kind {
    "adaptive" => {
      let display = match value.get("display") {
        Some(String("omitted")) => Some(AnthropicThinkingOmitted)
        Some(String("summarized")) => Some(AnthropicThinkingSummarized)
        Some(_) => {
          invalid_anthropic_option(
            reader, "thinking.display", "Expected omitted or summarized; the invalid value was ignored.",
          )
          None
        }
        None => None
      }
      Some(AnthropicThinkingAdaptive(display))
    }
    "enabled" => {
      let budget_tokens = match value.get("budgetTokens") {
        Some(Number(number, ..)) =>
          match @provider_utils.json_number_as_int(number) {
            Some(value) => Some(value)
            None => {
              invalid_anthropic_option(
                reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
              )
              None
            }
          }
        Some(_) => {
          invalid_anthropic_option(
            reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
          )
          None
        }
        None =>
          match value.get("budget_tokens") {
            Some(Number(number, ..)) => {
              reader.add_warning(
                @provider.Warning::Deprecated(
                  setting="providerOptions.thinking.budget_tokens",
                  message="Use 'providerOptions.thinking.budgetTokens'.",
                ),
              )
              match @provider_utils.json_number_as_int(number) {
                Some(value) => Some(value)
                None => {
                  invalid_anthropic_option(
                    reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
                  )
                  None
                }
              }
            }
            Some(_) => {
              invalid_anthropic_option(
                reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
              )
              None
            }
            None => None
          }
      }
      Some(AnthropicThinkingEnabled(budget_tokens))
    }
    "disabled" => Some(AnthropicThinkingDisabled)
    _ => {
      invalid_anthropic_option(
        reader, "thinking.type", "Expected adaptive, enabled, or disabled; thinking was ignored.",
      )
      None
    }
  }
}

///|
fn parse_metadata_user_id(
  reader : @provider_utils.ProviderOptionsReader,
) -> String? {
  guard reader.take_object("metadata") is Some(metadata) else { return None }
  match metadata.get("userId") {
    Some(String(value)) => Some(value)
    Some(_) => {
      invalid_anthropic_option(
        reader, "metadata.userId", "Expected a string; metadata.userId was ignored.",
      )
      None
    }
    None =>
      match metadata.get("user_id") {
        Some(String(value)) => {
          reader.add_warning(
            @provider.Warning::Deprecated(
              setting="providerOptions.metadata.user_id",
              message="Use 'providerOptions.metadata.userId'.",
            ),
          )
          Some(value)
        }
        Some(_) => {
          invalid_anthropic_option(
            reader, "metadata.userId", "Expected a string; metadata.userId was ignored.",
          )
          None
        }
        None => None
      }
  }
}

///|
fn parse_string_array(
  reader : @provider_utils.ProviderOptionsReader,
  field : String,
  aliases : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  guard reader.take_array(field, aliases~) is Some(values) else {
    return result
  }
  for value in values {
    match value {
      String(item) => result.push(item)
      _ =>
        invalid_anthropic_option(
          reader, field, "Expected an array of strings; invalid entries were ignored.",
        )
    }
  }
  result
}

///|
fn parse_anthropic_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> ParsedAnthropicOptions {
  let resolution = resolve_anthropic_options(provider_options, provider_name)
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let send_reasoning = reader
    .take_bool("sendReasoning", aliases=["send_reasoning"])
    .unwrap_or(true)
  let structured_output_mode = reader
    .take_string("structuredOutputMode", aliases=["structured_output_mode"], allowed=[
      "outputFormat", "jsonTool", "auto",
    ])
    .unwrap_or("auto")
  let thinking = parse_anthropic_thinking(reader)
  let disable_parallel_tool_use = reader.take_bool("disableParallelToolUse", aliases=[
    "disable_parallel_tool_use",
  ])
  let cache_control = reader.take_json("cacheControl", aliases=["cache_control"])
  let metadata_user_id = parse_metadata_user_id(reader)
  let mcp_servers = reader
    .take_array("mcpServers", aliases=["mcp_servers"])
    .unwrap_or([])
  let container = reader.take_json("container")
  let tool_streaming = reader
    .take_bool("toolStreaming", aliases=["tool_streaming"])
    .unwrap_or(true)
  let effort = reader.take_string("effort", allowed=[
    "low", "medium", "high", "xhigh", "max",
  ])
  let task_budget = reader.take_json("taskBudget", aliases=["task_budget"])
  let speed = reader.take_string("speed", allowed=["fast", "standard"])
  let inference_geo = reader.take_string(
    "inferenceGeo",
    aliases=["inference_geo"],
    allowed=["us", "global"],
  )
  let fallbacks = reader.take_json("fallbacks")
  let beta_features = parse_string_array(reader, "anthropicBeta", [
    "anthropic_beta",
  ])
  let context_management = reader.take_json("contextManagement", aliases=[
    "context_management",
  ])
  {
    options: {
      send_reasoning,
      structured_output_mode,
      thinking,
      disable_parallel_tool_use,
      cache_control,
      metadata_user_id,
      mcp_servers,
      container,
      tool_streaming,
      effort,
      task_budget,
      speed,
      inference_geo,
      fallbacks,
      beta_features,
      context_management,
    },
    warnings: reader.diagnostics(),
  }
}

///|
fn reasoning_budget(max_output_tokens : Int, percentage : Int) -> Int {
  let computed = (max_output_tokens * percentage + 50) / 100
  if computed < 1024 {
    1024
  } else if computed > max_output_tokens {
    max_output_tokens
  } else {
    computed
  }
}

///|
fn map_anthropic_reasoning(
  effort : @provider.ReasoningEffort,
  capabilities : AnthropicModelCapabilities,
  warnings : Array[@provider.Warning],
) -> (AnthropicThinking?, String?) {
  match effort {
    @provider.ProviderDefault => (None, None)
    @provider.Disabled => (Some(AnthropicThinkingDisabled), None)
    @provider.Minimal | @provider.Low if capabilities.supports_adaptive_thinking =>
      (
        Some(AnthropicThinkingAdaptive(Some(AnthropicThinkingSummarized))),
        Some("low"),
      )
    @provider.Medium if capabilities.supports_adaptive_thinking =>
      (
        Some(AnthropicThinkingAdaptive(Some(AnthropicThinkingSummarized))),
        Some("medium"),
      )
    @provider.High if capabilities.supports_adaptive_thinking =>
      (
        Some(AnthropicThinkingAdaptive(Some(AnthropicThinkingSummarized))),
        Some("high"),
      )
    @provider.XHigh if capabilities.supports_adaptive_thinking =>
      if capabilities.supports_xhigh_effort {
        (
          Some(AnthropicThinkingAdaptive(Some(AnthropicThinkingSummarized))),
          Some("xhigh"),
        )
      } else {
        warnings.push(
          @provider.Warning::Compatibility(
            feature="reasoning",
            details="xhigh reasoning is mapped to Anthropic max effort for this model.",
          ),
        )
        (
          Some(AnthropicThinkingAdaptive(Some(AnthropicThinkingSummarized))),
          Some("max"),
        )
      }
    @provider.Minimal =>
      (
        Some(
          AnthropicThinkingEnabled(
            Some(reasoning_budget(capabilities.max_output_tokens, 2)),
          ),
        ),
        None,
      )
    @provider.Low =>
      (
        Some(
          AnthropicThinkingEnabled(
            Some(reasoning_budget(capabilities.max_output_tokens, 10)),
          ),
        ),
        None,
      )
    @provider.Medium =>
      (
        Some(
          AnthropicThinkingEnabled(
            Some(reasoning_budget(capabilities.max_output_tokens, 30)),
          ),
        ),
        None,
      )
    @provider.High =>
      (
        Some(
          AnthropicThinkingEnabled(
            Some(reasoning_budget(capabilities.max_output_tokens, 60)),
          ),
        ),
        None,
      )
    @provider.XHigh =>
      (
        Some(
          AnthropicThinkingEnabled(
            Some(reasoning_budget(capabilities.max_output_tokens, 90)),
          ),
        ),
        None,
      )
  }
}

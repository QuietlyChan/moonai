///|
/// DeepSeek chat model identifier.
pub type DeepSeekChatModelId = String

///|
/// Provider-specific DeepSeek chat options.
pub(all) struct DeepSeekLanguageModelChatOptions {
  thinking_type : String?
  reasoning_effort : String?
  strict_json_schema : Bool
} derive(Debug, Eq)

///|
/// Construct validated DeepSeek chat options.
pub fn DeepSeekLanguageModelChatOptions::new(
  thinking_type? : String,
  reasoning_effort? : String,
  strict_json_schema? : Bool = true,
) -> DeepSeekLanguageModelChatOptions raise {
  if thinking_type is Some(value) {
    guard value == "adaptive" || value == "enabled" || value == "disabled" else {
      fail("DeepSeek thinking_type must be adaptive, enabled, or disabled")
    }
  }
  if reasoning_effort is Some(value) {
    guard value == "low" ||
      value == "medium" ||
      value == "high" ||
      value == "xhigh" ||
      value == "max" else {
      fail("DeepSeek reasoning_effort must be low, medium, high, xhigh, or max")
    }
  }
  { thinking_type, reasoning_effort, strict_json_schema }
}

///|
/// Convert DeepSeek chat options into the provider-options namespace.
pub fn DeepSeekLanguageModelChatOptions::to_provider_options(
  self : DeepSeekLanguageModelChatOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.thinking_type is Some(value) {
    values["thinking"] = { "type": value }
  }
  if self.reasoning_effort is Some(value) {
    values["reasoningEffort"] = Json::string(value)
  }
  values["strictJsonSchema"] = Json::boolean(self.strict_json_schema)
  Map([("deepseek", Json::object(values))])
}

///|
priv struct ParsedDeepSeekChatOptions {
  options : DeepSeekLanguageModelChatOptions
  warnings : Array[@provider.Warning]
}

///|
fn parse_deepseek_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> ParsedDeepSeekChatOptions {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name~,
    aliases=["deepseek"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let thinking_type = match reader.take_object("thinking") {
    Some(value) =>
      match value.get("type") {
        Some(String(kind)) if kind == "adaptive" ||
          kind == "enabled" ||
          kind == "disabled" => Some(kind)
        Some(_) => {
          reader.add_warning(
            @provider.Warning::Compatibility(
              feature="providerOptions.deepseek.thinking.type",
              details="Expected adaptive, enabled, or disabled; the invalid value was ignored.",
            ),
          )
          None
        }
        None => None
      }
    None => None
  }
  let options = {
    thinking_type,
    reasoning_effort: reader.take_string(
      "reasoningEffort",
      aliases=["reasoning_effort"],
      allowed=["low", "medium", "high", "xhigh", "max"],
    ),
    strict_json_schema: reader
    .take_bool("strictJsonSchema", aliases=["strict_json_schema"])
    .unwrap_or(true),
  }
  { options, warnings: reader.diagnostics() }
}

///|
fn deepseek_reasoning_effort(
  effort : @provider.ReasoningEffort,
  warnings : Array[@provider.Warning],
) -> String? {
  match effort {
    @provider.ProviderDefault | @provider.Disabled => None
    @provider.Minimal => {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="reasoning",
          details="reasoning \"minimal\" is not directly supported by this model; mapped to effort \"low\".",
        ),
      )
      Some("low")
    }
    @provider.Low => Some("low")
    @provider.Medium => Some("medium")
    @provider.High => Some("high")
    @provider.XHigh => {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="reasoning",
          details="reasoning \"xhigh\" is not directly supported by this model; mapped to effort \"max\".",
        ),
      )
      Some("max")
    }
  }
}

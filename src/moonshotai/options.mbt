///|
/// Model identifier accepted by the Moonshot AI Chat Completions API.
pub type MoonshotAIChatModelId = String

///|
/// Moonshot model families with distinct thinking and reasoning behavior.
pub(all) enum MoonshotAIModelFamily {
  KimiK25
  KimiK26
  KimiK27
  KimiK3
  MoonshotV1
  Unknown
} derive(Debug, Eq)

///|
/// Detect the Moonshot model family for a model id.
pub fn get_moonshot_ai_model_family(model_id : String) -> MoonshotAIModelFamily {
  if model_id == "kimi-k2.5" {
    KimiK25
  } else if model_id == "kimi-k2.6" {
    KimiK26
  } else if model_id == "kimi-k2.7-code" ||
    model_id == "kimi-k2.7-code-highspeed" {
    KimiK27
  } else if model_id == "kimi-k3" {
    KimiK3
  } else if model_id.has_prefix("moonshot-v1-") {
    MoonshotV1
  } else {
    Unknown
  }
}

///|
/// Kimi models fix the sampling controls; they reject
/// temperature/top_p/penalties outright.
pub fn is_moonshot_ai_kimi_model(model_id : String) -> Bool {
  match get_moonshot_ai_model_family(model_id) {
    KimiK25 | KimiK26 | KimiK27 | KimiK3 => true
    MoonshotV1 | Unknown => false
  }
}

///|
fn moonshot_model_family_name(family : MoonshotAIModelFamily) -> String {
  match family {
    KimiK25 => "kimi-k2.5"
    KimiK26 => "kimi-k2.6"
    KimiK27 => "kimi-k2.7"
    KimiK3 => "kimi-k3"
    MoonshotV1 => "moonshot-v1"
    Unknown => "unknown"
  }
}

///|
/// AI SDK-style camel-case alias.
pub fn getMoonshotAIModelFamily(model_id : String) -> String {
  moonshot_model_family_name(get_moonshot_ai_model_family(model_id))
}

///|
/// Return whether a Moonshot model supports native JSON Schema output.
///
/// Official `moonshot-v1-*` models support structured output alongside the
/// Kimi K series (AI SDK #19583).
pub fn get_model_structured_output_support(model_id : String) -> Bool {
  model_id.has_prefix("kimi-k") ||
  model_id == "moonshot-v1-8k" ||
  model_id == "moonshot-v1-32k" ||
  model_id == "moonshot-v1-128k" ||
  model_id == "moonshot-v1-auto" ||
  model_id == "moonshot-v1-8k-vision-preview" ||
  model_id == "moonshot-v1-32k-vision-preview" ||
  model_id == "moonshot-v1-128k-vision-preview"
}

///|
/// AI SDK-style camel-case alias.
pub fn getModelStructuredOutputSupport(model_id : String) -> Bool {
  get_model_structured_output_support(model_id)
}

///|
/// Provider-specific options for Moonshot AI language models.
pub(all) struct MoonshotAILanguageModelOptions {
  strict_json_schema : Bool?
  logprobs : Bool?
  top_logprobs : Int?
  reasoning_effort : String?
  prediction : Json?
  thinking_type : String?
  thinking_budget_tokens : Int?
  reasoning_history : String?
  prompt_cache_key : String?
  safety_identifier : String?
} derive(Debug, Eq)

///|
/// Construct validated Moonshot AI language-model options.
pub fn MoonshotAILanguageModelOptions::new(
  strict_json_schema? : Bool,
  logprobs? : Bool,
  top_logprobs? : Int,
  reasoning_effort? : String,
  prediction? : Json,
  thinking_type? : String,
  thinking_budget_tokens? : Int,
  reasoning_history? : String,
  prompt_cache_key? : String,
  safety_identifier? : String,
) -> MoonshotAILanguageModelOptions raise {
  if top_logprobs is Some(value) {
    guard value >= 0 && value <= 20 else {
      fail("Moonshot AI top_logprobs must be between 0 and 20")
    }
  }
  if reasoning_effort is Some(value) {
    guard value == "low" || value == "high" || value == "max" else {
      fail("Moonshot AI reasoning_effort must be low, high, or max")
    }
  }
  if thinking_type is Some(value) {
    guard value == "enabled" || value == "disabled" else {
      fail("Moonshot AI thinking_type must be enabled or disabled")
    }
  }
  if thinking_budget_tokens is Some(value) {
    guard value >= 1024 else {
      fail("Moonshot AI thinking_budget_tokens must be at least 1024")
    }
  }
  if reasoning_history is Some(value) {
    guard value == "disabled" || value == "interleaved" || value == "preserved" else {
      fail(
        "Moonshot AI reasoning_history must be disabled, interleaved, or preserved",
      )
    }
  }
  {
    strict_json_schema,
    logprobs,
    top_logprobs,
    reasoning_effort,
    prediction,
    thinking_type,
    thinking_budget_tokens,
    reasoning_history,
    prompt_cache_key,
    safety_identifier,
  }
}

///|
/// Convert typed options to AI SDK's `providerOptions.moonshotai` namespace.
pub fn MoonshotAILanguageModelOptions::to_provider_options(
  self : MoonshotAILanguageModelOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.strict_json_schema is Some(value) {
    values["strictJsonSchema"] = Json::boolean(value)
  }
  if self.logprobs is Some(value) {
    values["logprobs"] = Json::boolean(value)
  }
  if self.top_logprobs is Some(value) {
    values["topLogprobs"] = Json::number(value.to_double())
  }
  if self.reasoning_effort is Some(value) {
    values["reasoningEffort"] = Json::string(value)
  }
  if self.prediction is Some(value) {
    values["prediction"] = value
  }
  let has_thinking = match self.thinking_type {
    Some(_) => true
    None => self.thinking_budget_tokens is Some(_)
  }
  if has_thinking {
    let thinking : Map[String, Json] = Map([])
    if self.thinking_type is Some(value) {
      thinking["type"] = Json::string(value)
    }
    if self.thinking_budget_tokens is Some(tokens) {
      thinking["budgetTokens"] = Json::number(tokens.to_double())
    }
    values["thinking"] = Json::object(thinking)
  }
  if self.reasoning_history is Some(value) {
    values["reasoningHistory"] = Json::string(value)
  }
  if self.prompt_cache_key is Some(value) {
    values["promptCacheKey"] = Json::string(value)
  }
  if self.safety_identifier is Some(value) {
    values["safetyIdentifier"] = Json::string(value)
  }
  Map([("moonshotai", Json::object(values))])
}

///|
priv struct ParsedMoonshotChatOptions {
  options : MoonshotAILanguageModelOptions
  warnings : Array[@provider.Warning]
}

///|
fn parse_moonshot_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> ParsedMoonshotChatOptions {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name~,
    aliases=["moonshotai"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let strict_json_schema = reader.take_bool("strictJsonSchema", aliases=[
    "strict_json_schema",
  ])
  let logprobs = reader.take_bool("logprobs")
  let top_logprobs = reader.take_int(
    "topLogprobs",
    aliases=["top_logprobs"],
    min=0,
    max=20,
  )
  let reasoning_effort = reader.take_string(
    "reasoningEffort",
    aliases=["reasoning_effort"],
    allowed=["low", "high", "max"],
  )
  let prediction = match reader.take_object("prediction") {
    Some(value) => Some(Json::object(value))
    None => None
  }
  let thinking_type : String? = match reader.take_object("thinking") {
    Some(thinking) =>
      match thinking.get("type") {
        Some(String(value)) if value == "enabled" || value == "disabled" =>
          Some(value)
        Some(String(_)) => {
          reader.add_warning(
            @provider.Warning::Compatibility(
              feature="providerOptions.moonshotai.thinking.type",
              details="Expected enabled or disabled; the invalid value was ignored.",
            ),
          )
          None
        }
        _ => None
      }
    None => None
  }
  let thinking_budget_tokens : Int? = match reader.take_object("thinking") {
    Some(thinking) =>
      match thinking.get("budgetTokens") {
        Some(Number(value, ..)) => Some(value.to_int())
        _ => None
      }
    None => None
  }
  let reasoning_history = reader.take_string(
    "reasoningHistory",
    aliases=["reasoning_history"],
    allowed=["disabled", "interleaved", "preserved"],
  )
  let prompt_cache_key = reader.take_string("promptCacheKey", aliases=[
    "prompt_cache_key",
  ])
  let safety_identifier = reader.take_string("safetyIdentifier", aliases=[
    "safety_identifier",
  ])
  {
    options: {
      strict_json_schema,
      logprobs,
      top_logprobs,
      reasoning_effort,
      prediction,
      thinking_type,
      thinking_budget_tokens,
      reasoning_history,
      prompt_cache_key,
      safety_identifier,
    },
    warnings: reader.diagnostics(),
  }
}

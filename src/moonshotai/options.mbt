///|
/// Model identifier accepted by the Moonshot AI Chat Completions API.
pub type MoonshotAIChatModelId = String

///|
/// Provider-specific options for Moonshot AI language models.
pub(all) struct MoonshotAILanguageModelOptions {
  reasoning_effort : String?
  thinking_type : String?
  thinking_budget_tokens : Int?
  reasoning_history : String?
} derive(Debug, Eq)

///|
/// Construct validated Moonshot AI language-model options.
pub fn MoonshotAILanguageModelOptions::new(
  reasoning_effort? : String,
  thinking_type? : String,
  thinking_budget_tokens? : Int,
  reasoning_history? : String,
) -> MoonshotAILanguageModelOptions raise {
  if reasoning_effort is Some(value) {
    guard value == "max" else {
      fail("Moonshot AI reasoning_effort currently supports only max")
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
  { reasoning_effort, thinking_type, thinking_budget_tokens, reasoning_history }
}

///|
/// Convert typed options to AI SDK's `providerOptions.moonshotai` namespace.
pub fn MoonshotAILanguageModelOptions::to_provider_options(
  self : MoonshotAILanguageModelOptions,
) -> Map[String, Json] {
  let values : Map[String, Json] = Map([])
  if self.reasoning_effort is Some(value) {
    values["reasoningEffort"] = Json::string(value)
  }
  if self.thinking_type is Some(value) {
    let thinking : Map[String, Json] = Map([("type", Json::string(value))])
    if self.thinking_budget_tokens is Some(tokens) {
      thinking["budgetTokens"] = Json::number(tokens.to_double())
    }
    values["thinking"] = Json::object(thinking)
  }
  if self.reasoning_history is Some(value) {
    values["reasoningHistory"] = Json::string(value)
  }
  Map([("moonshotai", Json::object(values))])
}

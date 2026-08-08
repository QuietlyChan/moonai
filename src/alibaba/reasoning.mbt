///|
/// Return whether Alibaba thinking fields were explicitly supplied by the
/// caller. Explicit provider options take precedence over normalized reasoning,
/// matching the AI SDK provider contract.
fn alibaba_has_explicit_reasoning_options(
  provider_options : Map[String, Json],
) -> Bool {
  let resolution = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="alibaba.chat",
    aliases=["alibaba"],
  )
  for
    key in [
      "enableThinking", "enable_thinking", "thinkingBudget", "thinking_budget",
    ] {
    if resolution.values.get(key) is Some(_) {
      return true
    }
  }
  false
}

///|
/// Translate the normalized reasoning setting into Alibaba's Qwen options.
fn alibaba_reasoning_provider_options(
  effort : @provider.ReasoningEffort,
) -> Map[String, Json] {
  match effort {
    @provider.ProviderDefault => Map([])
    @provider.Disabled => { "alibaba": { "enableThinking": false } }
    _ => {
      let warnings : Array[@provider.Warning] = []
      let budget = @provider_utils.map_reasoning_to_provider_budget(
        effort, 16_384, 16_384, warnings,
      )
      let values : Map[String, Json] = Map([
        ("enableThinking", Json::boolean(true)),
      ])
      match budget {
        Some(value) =>
          values["thinkingBudget"] = Json::number(value.to_double())
        None => ()
      }
      Map([("alibaba", Json::object(values))])
    }
  }
}

///|
/// Apply Alibaba's normalized reasoning mapping to a native V4 call.
fn alibaba_apply_reasoning_v4(
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4CallOptions {
  match options.reasoning {
    @provider.V4ReasoningProviderDefault => options
    effort => {
      let legacy_effort = effort.to_reasoning_effort()
      let effective = if !alibaba_has_explicit_reasoning_options(
          options.provider_options,
        ) {
        options.with_provider_options(
          alibaba_reasoning_provider_options(legacy_effort),
        )
      } else {
        options
      }
      effective.with_reasoning(@provider.V4ReasoningProviderDefault)
    }
  }
}

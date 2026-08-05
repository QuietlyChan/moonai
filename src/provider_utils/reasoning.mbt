///|
/// Return whether a reasoning setting overrides the provider default.
///
/// This mirrors AI SDK's `isCustomReasoning`: `ProviderDefault` is the only
/// value that leaves provider behavior untouched. `Disabled` is intentional
/// user input and therefore remains a custom setting.
pub fn is_custom_reasoning(reasoning : @provider.ReasoningEffort) -> Bool {
  match reasoning {
    @provider.ProviderDefault => false
    _ => true
  }
}

///|
/// Camel-case alias matching the AI SDK utility name.
pub fn isCustomReasoning(reasoning : @provider.ReasoningEffort) -> Bool {
  is_custom_reasoning(reasoning)
}

///|
fn reasoning_key(reasoning : @provider.ReasoningEffort) -> String {
  match reasoning {
    @provider.ProviderDefault => "provider-default"
    @provider.Disabled => "none"
    @provider.Minimal => "minimal"
    @provider.Low => "low"
    @provider.Medium => "medium"
    @provider.High => "high"
    @provider.XHigh => "xhigh"
  }
}

///|
/// Map a normalized reasoning level to a provider-specific effort string.
///
/// Missing entries produce the same unsupported warning as AI SDK and return
/// `None`. A mapped value with a different spelling produces a compatibility
/// warning so callers can surface the adaptation without failing the request.
pub fn map_reasoning_to_provider_effort(
  reasoning : @provider.ReasoningEffort,
  effort_map : Map[String, String],
  warnings : Array[@provider.Warning],
) -> String? {
  let key = reasoning_key(reasoning)
  match effort_map.get(key) {
    Some(mapped) => {
      if mapped != key {
        warnings.push(
          @provider.Warning::Compatibility(
            feature="reasoning",
            details="reasoning \"\{key}\" is not directly supported by this model; mapped to effort \"\{mapped}\".",
          ),
        )
      }
      Some(mapped)
    }
    None => {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoning",
          details="reasoning \"\{key}\" is not supported by this model.",
        ),
      )
      None
    }
  }
}

///|
/// Camel-case alias matching the AI SDK utility name.
pub fn mapReasoningToProviderEffort(
  reasoning : @provider.ReasoningEffort,
  effort_map : Map[String, String],
  warnings : Array[@provider.Warning],
) -> String? {
  map_reasoning_to_provider_effort(reasoning, effort_map, warnings)
}

///|
fn default_reasoning_budget_percentages() -> Map[String, Double] {
  Map([
    ("minimal", 0.02),
    ("low", 0.1),
    ("medium", 0.3),
    ("high", 0.6),
    ("xhigh", 0.9),
  ])
}

///|
/// Map a normalized reasoning level to an absolute provider token budget.
///
/// The percentage table and clamping rules follow AI SDK's
/// `mapReasoningToProviderBudget`. `ProviderDefault` and `Disabled` do not
/// request a budget and return `None` without a warning; providers normally
/// handle those two states separately.
pub fn map_reasoning_to_provider_budget(
  reasoning : @provider.ReasoningEffort,
  max_output_tokens : Int,
  max_reasoning_budget : Int,
  warnings : Array[@provider.Warning],
  min_reasoning_budget? : Int = 1024,
  budget_percentages? : Map[String, Double],
) -> Int? {
  let key = reasoning_key(reasoning)
  match reasoning {
    @provider.ProviderDefault | @provider.Disabled => None
    _ => {
      let percentages = budget_percentages.unwrap_or(
        default_reasoning_budget_percentages(),
      )
      match percentages.get(key) {
        Some(percentage) => {
          let computed = (max_output_tokens.to_double() * percentage)
            .round()
            .to_int()
          let upper = max_reasoning_budget.max(0)
          let lower = min_reasoning_budget.max(0).min(upper)
          Some(computed.max(lower).min(upper))
        }
        None => {
          warnings.push(
            @provider.Warning::Unsupported(
              feature="reasoning",
              details="reasoning \"\{key}\" is not supported by this model.",
            ),
          )
          None
        }
      }
    }
  }
}

///|
/// Camel-case alias matching the AI SDK utility name.
pub fn mapReasoningToProviderBudget(
  reasoning : @provider.ReasoningEffort,
  max_output_tokens : Int,
  max_reasoning_budget : Int,
  warnings : Array[@provider.Warning],
  min_reasoning_budget? : Int = 1024,
  budget_percentages? : Map[String, Double],
) -> Int? {
  map_reasoning_to_provider_budget(
    reasoning,
    max_output_tokens,
    max_reasoning_budget,
    warnings,
    min_reasoning_budget~,
    budget_percentages?,
  )
}

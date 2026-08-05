///|
/// Anthropic model identifiers are open strings so newly released Claude
/// models can be used without waiting for a moonai release.
pub type AnthropicModelId = String

///|
fn anthropic_typed_namespace(
  provider_name : String,
  fields : Map[String, Json],
) -> Map[String, Json] {
  Map([(provider_name, Json::object(fields))])
}

///|
fn anthropic_string_array_json(values : Array[String]) -> Json {
  Json::array([ for value in values => Json::string(value) ])
}

///|
fn anthropic_provider_reference_json(
  reference : @provider.ProviderReference,
) -> Json {
  let fields : Map[String, Json] = Map([])
  for provider_name in reference.providers() {
    if reference.get(provider_name) is Some(id) {
      fields[provider_name] = Json::string(id)
    }
  }
  Json::object(fields)
}

///|
/// Citation settings attached to an Anthropic document part.
pub(all) struct AnthropicCitations {
  enabled : Bool
} derive(Debug, Eq)

///|
/// Construct document citation settings.
pub fn AnthropicCitations::new(enabled~ : Bool) -> AnthropicCitations {
  { enabled, }
}

///|
/// Provider options accepted on an Anthropic file content part.
pub(all) struct AnthropicFilePartProviderOptions {
  container_upload : Bool?
  citations : AnthropicCitations?
  title : String?
  context : String?
} derive(Debug, Eq)

///|
/// Construct typed options for one Anthropic file part.
pub fn AnthropicFilePartProviderOptions::new(
  container_upload? : Bool,
  citations? : AnthropicCitations,
  title? : String,
  context? : String,
) -> AnthropicFilePartProviderOptions {
  { container_upload, citations, title, context }
}

///|
/// Convert typed file-part settings to an Anthropic provider namespace.
pub fn AnthropicFilePartProviderOptions::to_provider_options(
  self : AnthropicFilePartProviderOptions,
  provider_name? : String = "anthropic",
) -> Map[String, Json] {
  anthropic_typed_namespace(
    provider_name,
    Map(
      [
        ..if self.container_upload is Some(value) {
          [("containerUpload", Json::boolean(value))]
        },
        ..if self.citations is Some(value) {
          [("citations", ({ "enabled": value.enabled } : Json))]
        },
        ..if self.title is Some(value) {
          [("title", Json::string(value))]
        },
        ..if self.context is Some(value) {
          [("context", Json::string(value))]
        },
      ],
    ),
  )
}

///|
/// A tool addition or removal attached to a mid-conversation system message.
pub(all) enum AnthropicToolChange {
  AnthropicToolAddition(String)
  AnthropicToolRemoval(String)
} derive(Debug, Eq)

///|
/// Add a function tool to the mid-conversation tool set.
pub fn AnthropicToolChange::addition(tool_name : String) -> AnthropicToolChange {
  AnthropicToolAddition(tool_name)
}

///|
/// Remove a function tool from the mid-conversation tool set.
pub fn AnthropicToolChange::removal(tool_name : String) -> AnthropicToolChange {
  AnthropicToolRemoval(tool_name)
}

///|
fn AnthropicToolChange::to_json(self : AnthropicToolChange) -> Json {
  match self {
    AnthropicToolAddition(tool_name) =>
      ({ "type": "tool_addition", "toolName": tool_name } : Json)
    AnthropicToolRemoval(tool_name) =>
      ({ "type": "tool_removal", "toolName": tool_name } : Json)
  }
}

///|
/// Provider options accepted on an Anthropic system message.
pub(all) struct AnthropicSystemMessageProviderOptions {
  tool_changes : Array[AnthropicToolChange]
} derive(Debug, Eq)

///|
/// Construct typed options for an Anthropic system message.
pub fn AnthropicSystemMessageProviderOptions::new(
  tool_changes? : Array[AnthropicToolChange] = [],
) -> AnthropicSystemMessageProviderOptions {
  { tool_changes: tool_changes.copy() }
}

///|
/// Convert typed system-message settings to an Anthropic provider namespace.
pub fn AnthropicSystemMessageProviderOptions::to_provider_options(
  self : AnthropicSystemMessageProviderOptions,
  provider_name? : String = "anthropic",
) -> Map[String, Json] {
  anthropic_typed_namespace(
    provider_name,
    Map(
      [
        ..if self.tool_changes.length() > 0 {
          [
            (
              "toolChanges",
              Json::array(
                [
                  for change in self.tool_changes => change.to_json()
                ],
              ),
            ),
          ]
        },
      ],
    ),
  )
}

///|
/// Strategy used to implement structured output on Anthropic models.
pub(all) enum AnthropicStructuredOutputMode {
  AnthropicStructuredOutputFormat
  AnthropicStructuredOutputJsonTool
  AnthropicStructuredOutputAuto
} derive(Debug, Eq)

///|
fn AnthropicStructuredOutputMode::wire_name(
  self : AnthropicStructuredOutputMode,
) -> String {
  match self {
    AnthropicStructuredOutputFormat => "outputFormat"
    AnthropicStructuredOutputJsonTool => "jsonTool"
    AnthropicStructuredOutputAuto => "auto"
  }
}

///|
/// Visibility of adaptive thinking content in the response.
pub(all) enum AnthropicThinkingDisplay {
  AnthropicThinkingOmitted
  AnthropicThinkingSummarized
} derive(Debug, Eq)

///|
fn AnthropicThinkingDisplay::wire_name(
  self : AnthropicThinkingDisplay,
) -> String {
  match self {
    AnthropicThinkingOmitted => "omitted"
    AnthropicThinkingSummarized => "summarized"
  }
}

///|
/// Anthropic extended-thinking configuration.
pub(all) enum AnthropicThinking {
  AnthropicThinkingAdaptive(AnthropicThinkingDisplay?)
  AnthropicThinkingEnabled(Int?)
  AnthropicThinkingDisabled
} derive(Debug, Eq)

///|
/// Enable adaptive thinking and optionally select its response visibility.
pub fn AnthropicThinking::adaptive(
  display? : AnthropicThinkingDisplay,
) -> AnthropicThinking {
  AnthropicThinkingAdaptive(display)
}

///|
/// Enable budget-based extended thinking.
pub fn AnthropicThinking::enabled(budget_tokens? : Int) -> AnthropicThinking {
  AnthropicThinkingEnabled(budget_tokens)
}

///|
/// Explicitly disable thinking for models that enable it by default.
pub fn AnthropicThinking::disabled() -> AnthropicThinking {
  AnthropicThinkingDisabled
}

///|
fn AnthropicThinking::to_provider_json(self : AnthropicThinking) -> Json {
  match self {
    AnthropicThinkingAdaptive(display) =>
      Json::object(
        Map(
          [
            ("type", Json::string("adaptive")),
            ..if display is Some(value) {
              [("display", Json::string(value.wire_name()))]
            },
          ],
        ),
      )
    AnthropicThinkingEnabled(budget_tokens) =>
      Json::object(
        Map(
          [
            ("type", Json::string("enabled")),
            ..if budget_tokens is Some(value) {
              [("budgetTokens", Json::number(value.to_double()))]
            },
          ],
        ),
      )
    AnthropicThinkingDisabled => ({ "type": "disabled" } : Json)
  }
}

///|
/// Prompt-cache lifetime supported by Anthropic.
pub(all) enum AnthropicCacheTtl {
  AnthropicCacheFiveMinutes
  AnthropicCacheOneHour
} derive(Debug, Eq)

///|
fn AnthropicCacheTtl::wire_name(self : AnthropicCacheTtl) -> String {
  match self {
    AnthropicCacheFiveMinutes => "5m"
    AnthropicCacheOneHour => "1h"
  }
}

///|
/// Anthropic request-level cache-control settings.
pub(all) struct AnthropicCacheControl {
  ttl : AnthropicCacheTtl?
} derive(Debug, Eq)

///|
/// Construct ephemeral Anthropic cache-control settings.
pub fn AnthropicCacheControl::new(
  ttl? : AnthropicCacheTtl,
) -> AnthropicCacheControl {
  { ttl, }
}

///|
fn AnthropicCacheControl::to_json(self : AnthropicCacheControl) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("ephemeral")),
        ..if self.ttl is Some(value) {
          [("ttl", Json::string(value.wire_name()))]
        },
      ],
    ),
  )
}

///|
/// Request metadata accepted by Anthropic Messages.
pub(all) struct AnthropicMetadata {
  user_id : String?
} derive(Debug, Eq)

///|
/// Construct Anthropic request metadata with an opaque user identifier.
pub fn AnthropicMetadata::new(user_id? : String) -> AnthropicMetadata {
  { user_id, }
}

///|
fn AnthropicMetadata::to_json(self : AnthropicMetadata) -> Json {
  Json::object(
    Map(
      [..if self.user_id is Some(value) { [("userId", Json::string(value))] }],
    ),
  )
}

///|
/// Tool filtering applied to one Anthropic MCP server.
pub(all) struct AnthropicMcpToolConfiguration {
  enabled : Bool?
  allowed_tools : Array[String]?
} derive(Debug, Eq)

///|
/// Construct MCP tool filtering settings.
pub fn AnthropicMcpToolConfiguration::new(
  enabled? : Bool,
  allowed_tools? : Array[String],
) -> AnthropicMcpToolConfiguration {
  { enabled, allowed_tools: allowed_tools.map(fn(values) { values.copy() }) }
}

///|
fn AnthropicMcpToolConfiguration::to_json(
  self : AnthropicMcpToolConfiguration,
) -> Json {
  Json::object(
    Map(
      [
        ..if self.enabled is Some(value) {
          [("enabled", Json::boolean(value))]
        },
        ..if self.allowed_tools is Some(values) {
          [("allowedTools", anthropic_string_array_json(values))]
        },
      ],
    ),
  )
}

///|
/// A URL-backed MCP server used directly by Anthropic.
pub(all) struct AnthropicMcpServer {
  name : String
  url : String
  authorization_token : String?
  tool_configuration : AnthropicMcpToolConfiguration?
} derive(Debug, Eq)

///|
/// Construct one URL-backed MCP server definition.
pub fn AnthropicMcpServer::new(
  name~ : String,
  url~ : String,
  authorization_token? : String,
  tool_configuration? : AnthropicMcpToolConfiguration,
) -> AnthropicMcpServer {
  { name, url, authorization_token, tool_configuration }
}

///|
fn AnthropicMcpServer::to_json(self : AnthropicMcpServer) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("url")),
        ("name", Json::string(self.name)),
        ("url", Json::string(self.url)),
        ..if self.authorization_token is Some(value) {
          [("authorizationToken", Json::string(value))]
        },
        ..if self.tool_configuration is Some(value) {
          [("toolConfiguration", value.to_json())]
        },
      ],
    ),
  )
}

///|
/// A built-in or uploaded skill mounted in an Anthropic container.
pub(all) enum AnthropicContainerSkill {
  AnthropicBuiltInSkill(skill_id~ : String, version~ : String?)
  AnthropicCustomSkill(
    provider_reference~ : @provider.ProviderReference,
    version~ : String?
  )
} derive(Debug, Eq)

///|
/// Reference a built-in Anthropic skill.
pub fn AnthropicContainerSkill::built_in(
  skill_id~ : String,
  version? : String,
) -> AnthropicContainerSkill {
  AnthropicBuiltInSkill(skill_id~, version~)
}

///|
/// Reference a provider-neutral uploaded skill.
pub fn AnthropicContainerSkill::custom(
  provider_reference~ : @provider.ProviderReference,
  version? : String,
) -> AnthropicContainerSkill {
  AnthropicCustomSkill(provider_reference~, version~)
}

///|
fn AnthropicContainerSkill::to_json(self : AnthropicContainerSkill) -> Json {
  match self {
    AnthropicBuiltInSkill(skill_id~, version~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("anthropic")),
            ("skillId", Json::string(skill_id)),
            ..if version is Some(value) {
              [("version", Json::string(value))]
            },
          ],
        ),
      )
    AnthropicCustomSkill(provider_reference~, version~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("custom")),
            (
              "providerReference",
              anthropic_provider_reference_json(provider_reference),
            ),
            ..if version is Some(value) {
              [("version", Json::string(value))]
            },
          ],
        ),
      )
  }
}

///|
/// Anthropic code-execution container settings.
pub(all) struct AnthropicContainer {
  id : String?
  skills : Array[AnthropicContainerSkill]
} derive(Debug, Eq)

///|
/// Construct Anthropic container reuse and skill-mount settings.
pub fn AnthropicContainer::new(
  id? : String,
  skills? : Array[AnthropicContainerSkill] = [],
) -> AnthropicContainer {
  { id, skills: skills.copy() }
}

///|
fn AnthropicContainer::to_json(self : AnthropicContainer) -> Json {
  Json::object(
    Map(
      [
        ..if self.id is Some(value) {
          [("id", Json::string(value))]
        },
        ..if self.skills.length() > 0 {
          [
            (
              "skills",
              Json::array([ for skill in self.skills => skill.to_json() ]),
            ),
          ]
        },
      ],
    ),
  )
}

///|
/// Anthropic output effort.
pub(all) enum AnthropicEffort {
  AnthropicEffortLow
  AnthropicEffortMedium
  AnthropicEffortHigh
  AnthropicEffortXHigh
  AnthropicEffortMax
} derive(Debug, Eq)

///|
fn AnthropicEffort::wire_name(self : AnthropicEffort) -> String {
  match self {
    AnthropicEffortLow => "low"
    AnthropicEffortMedium => "medium"
    AnthropicEffortHigh => "high"
    AnthropicEffortXHigh => "xhigh"
    AnthropicEffortMax => "max"
  }
}

///|
/// Advisory token budget for one agentic task.
pub(all) struct AnthropicTaskBudget {
  total : Int
  remaining : Int?
} derive(Debug, Eq)

///|
/// Construct and validate an Anthropic task token budget.
pub fn AnthropicTaskBudget::new(
  total~ : Int,
  remaining? : Int,
) -> AnthropicTaskBudget raise {
  guard total >= 20000 else {
    fail("Anthropic task budget total must be at least 20000")
  }
  if remaining is Some(value) {
    guard value >= 0 else {
      fail("Anthropic task budget remaining must be non-negative")
    }
  }
  { total, remaining }
}

///|
fn AnthropicTaskBudget::to_json(self : AnthropicTaskBudget) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("tokens")),
        ("total", Json::number(self.total.to_double())),
        ..if self.remaining is Some(value) {
          [("remaining", Json::number(value.to_double()))]
        },
      ],
    ),
  )
}

///|
/// Anthropic inference speed selection.
pub(all) enum AnthropicSpeed {
  AnthropicSpeedFast
  AnthropicSpeedStandard
} derive(Debug, Eq)

///|
fn AnthropicSpeed::wire_name(self : AnthropicSpeed) -> String {
  match self {
    AnthropicSpeedFast => "fast"
    AnthropicSpeedStandard => "standard"
  }
}

///|
/// Geography in which Anthropic inference may run.
pub(all) enum AnthropicInferenceGeo {
  AnthropicInferenceUs
  AnthropicInferenceGlobal
} derive(Debug, Eq)

///|
fn AnthropicInferenceGeo::wire_name(self : AnthropicInferenceGeo) -> String {
  match self {
    AnthropicInferenceUs => "us"
    AnthropicInferenceGlobal => "global"
  }
}

///|
/// One explicit server-side fallback attempt.
pub(all) struct AnthropicFallback {
  model : String
  max_tokens : Int?
  thinking : Map[String, Json]?
  output_config : Map[String, Json]?
  speed : AnthropicSpeed?
} derive(Debug, Eq)

///|
/// Construct one explicit Anthropic fallback attempt.
pub fn AnthropicFallback::new(
  model~ : String,
  max_tokens? : Int,
  thinking? : Map[String, Json],
  output_config? : Map[String, Json],
  speed? : AnthropicSpeed,
) -> AnthropicFallback {
  {
    model,
    max_tokens,
    thinking: thinking.map(fn(values) { values.copy() }),
    output_config: output_config.map(fn(values) { values.copy() }),
    speed,
  }
}

///|
fn AnthropicFallback::to_json(self : AnthropicFallback) -> Json {
  Json::object(
    Map(
      [
        ("model", Json::string(self.model)),
        ..if self.max_tokens is Some(value) {
          [("max_tokens", Json::number(value.to_double()))]
        },
        ..if self.thinking is Some(value) {
          [("thinking", Json::object(value))]
        },
        ..if self.output_config is Some(value) {
          [("output_config", Json::object(value))]
        },
        ..if self.speed is Some(value) {
          [("speed", Json::string(value.wire_name()))]
        },
      ],
    ),
  )
}

///|
/// Default or explicit server-side fallback routing.
pub(all) enum AnthropicFallbacks {
  AnthropicDefaultFallback
  AnthropicFallbackChain(Array[AnthropicFallback])
} derive(Debug, Eq)

///|
/// Use Anthropic's recommended server-side fallback.
pub fn AnthropicFallbacks::default_fallback() -> AnthropicFallbacks {
  AnthropicDefaultFallback
}

///|
/// Use an explicit ordered server-side fallback chain.
pub fn AnthropicFallbacks::chain(
  fallbacks : Array[AnthropicFallback],
) -> AnthropicFallbacks {
  AnthropicFallbackChain(fallbacks.copy())
}

///|
fn AnthropicFallbacks::to_json(self : AnthropicFallbacks) -> Json {
  match self {
    AnthropicDefaultFallback => Json::string("default")
    AnthropicFallbackChain(values) =>
      Json::array([ for value in values => value.to_json() ])
  }
}

///|
/// Trigger for clearing Anthropic-managed context.
pub(all) enum AnthropicContextTrigger {
  AnthropicContextInputTokens(Double)
  AnthropicContextToolUses(Double)
} derive(Debug, Eq)

///|
/// Trigger context editing at an input-token count.
pub fn AnthropicContextTrigger::input_tokens(
  value : Double,
) -> AnthropicContextTrigger {
  AnthropicContextInputTokens(value)
}

///|
/// Trigger context editing at a tool-use count.
pub fn AnthropicContextTrigger::tool_uses(
  value : Double,
) -> AnthropicContextTrigger {
  AnthropicContextToolUses(value)
}

///|
fn AnthropicContextTrigger::to_json(self : AnthropicContextTrigger) -> Json {
  match self {
    AnthropicContextInputTokens(value) =>
      ({ "type": "input_tokens", "value": value } : Json)
    AnthropicContextToolUses(value) =>
      ({ "type": "tool_uses", "value": value } : Json)
  }
}

///|
/// Number of recent tool uses retained by a clear-tool-uses edit.
pub(all) struct AnthropicToolUseKeep {
  value : Double
} derive(Debug, Eq)

///|
/// Retain a number of recent tool uses.
pub fn AnthropicToolUseKeep::new(value~ : Double) -> AnthropicToolUseKeep {
  { value, }
}

///|
fn AnthropicToolUseKeep::to_json(self : AnthropicToolUseKeep) -> Json {
  ({ "type": "tool_uses", "value": self.value } : Json)
}

///|
/// Minimum input-token count cleared by a clear-tool-uses edit.
pub(all) struct AnthropicInputTokenClearAtLeast {
  value : Double
} derive(Debug, Eq)

///|
/// Set the minimum number of input tokens cleared by an edit.
pub fn AnthropicInputTokenClearAtLeast::new(
  value~ : Double,
) -> AnthropicInputTokenClearAtLeast {
  { value, }
}

///|
fn AnthropicInputTokenClearAtLeast::to_json(
  self : AnthropicInputTokenClearAtLeast,
) -> Json {
  ({ "type": "input_tokens", "value": self.value } : Json)
}

///|
/// Thinking blocks retained by a clear-thinking edit.
pub(all) enum AnthropicThinkingKeep {
  AnthropicKeepAllThinking
  AnthropicKeepThinkingTurns(Double)
} derive(Debug, Eq)

///|
/// Retain all thinking blocks during a clear-thinking edit.
pub fn AnthropicThinkingKeep::all() -> AnthropicThinkingKeep {
  AnthropicKeepAllThinking
}

///|
/// Retain a number of recent thinking turns.
pub fn AnthropicThinkingKeep::turns(value : Double) -> AnthropicThinkingKeep {
  AnthropicKeepThinkingTurns(value)
}

///|
fn AnthropicThinkingKeep::to_json(self : AnthropicThinkingKeep) -> Json {
  match self {
    AnthropicKeepAllThinking => Json::string("all")
    AnthropicKeepThinkingTurns(value) =>
      ({ "type": "thinking_turns", "value": value } : Json)
  }
}

///|
/// Input-token trigger for a compaction edit.
pub(all) struct AnthropicCompactionTrigger {
  value : Double
} derive(Debug, Eq)

///|
/// Construct an input-token trigger for context compaction.
pub fn AnthropicCompactionTrigger::new(
  value~ : Double,
) -> AnthropicCompactionTrigger {
  { value, }
}

///|
fn AnthropicCompactionTrigger::to_json(
  self : AnthropicCompactionTrigger,
) -> Json {
  ({ "type": "input_tokens", "value": self.value } : Json)
}

///|
/// One Anthropic server-side context-management edit.
pub(all) enum AnthropicContextManagementEdit {
  AnthropicClearToolUses(
    trigger~ : AnthropicContextTrigger?,
    keep~ : AnthropicToolUseKeep?,
    clear_at_least~ : AnthropicInputTokenClearAtLeast?,
    clear_tool_inputs~ : Bool?,
    exclude_tools~ : Array[String]
  )
  AnthropicClearThinking(keep~ : AnthropicThinkingKeep?)
  AnthropicCompactContext(
    trigger~ : AnthropicCompactionTrigger?,
    pause_after_compaction~ : Bool?,
    instructions~ : String?
  )
} derive(Debug, Eq)

///|
/// Construct a clear-tool-uses context edit.
pub fn AnthropicContextManagementEdit::clear_tool_uses(
  trigger? : AnthropicContextTrigger,
  keep? : AnthropicToolUseKeep,
  clear_at_least? : AnthropicInputTokenClearAtLeast,
  clear_tool_inputs? : Bool,
  exclude_tools? : Array[String] = [],
) -> AnthropicContextManagementEdit {
  AnthropicClearToolUses(
    trigger~,
    keep~,
    clear_at_least~,
    clear_tool_inputs~,
    exclude_tools=exclude_tools.copy(),
  )
}

///|
/// Construct a clear-thinking context edit.
pub fn AnthropicContextManagementEdit::clear_thinking(
  keep? : AnthropicThinkingKeep,
) -> AnthropicContextManagementEdit {
  AnthropicClearThinking(keep~)
}

///|
/// Construct a server-side context compaction edit.
pub fn AnthropicContextManagementEdit::compact(
  trigger? : AnthropicCompactionTrigger,
  pause_after_compaction? : Bool,
  instructions? : String,
) -> AnthropicContextManagementEdit {
  AnthropicCompactContext(trigger~, pause_after_compaction~, instructions~)
}

///|
fn AnthropicContextManagementEdit::to_json(
  self : AnthropicContextManagementEdit,
) -> Json {
  match self {
    AnthropicClearToolUses(
      trigger~,
      keep~,
      clear_at_least~,
      clear_tool_inputs~,
      exclude_tools~
    ) =>
      Json::object(
        Map(
          [
            ("type", Json::string("clear_tool_uses_20250919")),
            ..if trigger is Some(value) {
              [("trigger", value.to_json())]
            },
            ..if keep is Some(value) {
              [("keep", value.to_json())]
            },
            ..if clear_at_least is Some(value) {
              [("clearAtLeast", value.to_json())]
            },
            ..if clear_tool_inputs is Some(value) {
              [("clearToolInputs", Json::boolean(value))]
            },
            ..if exclude_tools.length() > 0 {
              [("excludeTools", anthropic_string_array_json(exclude_tools))]
            },
          ],
        ),
      )
    AnthropicClearThinking(keep~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("clear_thinking_20251015")),
            ..if keep is Some(value) {
              [("keep", value.to_json())]
            },
          ],
        ),
      )
    AnthropicCompactContext(trigger~, pause_after_compaction~, instructions~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("compact_20260112")),
            ..if trigger is Some(value) {
              [("trigger", value.to_json())]
            },
            ..if pause_after_compaction is Some(value) {
              [("pauseAfterCompaction", Json::boolean(value))]
            },
            ..if instructions is Some(value) {
              [("instructions", Json::string(value))]
            },
          ],
        ),
      )
  }
}

///|
/// Anthropic server-side context-management configuration.
pub(all) struct AnthropicContextManagement {
  edits : Array[AnthropicContextManagementEdit]
} derive(Debug, Eq)

///|
/// Construct Anthropic server-side context management settings.
pub fn AnthropicContextManagement::new(
  edits~ : Array[AnthropicContextManagementEdit],
) -> AnthropicContextManagement {
  { edits: edits.copy() }
}

///|
fn AnthropicContextManagement::to_json(
  self : AnthropicContextManagement,
) -> Json {
  { "edits": [ for edit in self.edits => edit.to_json() ] }
}

///|
/// Typed provider options for Anthropic Messages language models.
pub(all) struct AnthropicLanguageModelOptions {
  send_reasoning : Bool?
  structured_output_mode : AnthropicStructuredOutputMode?
  thinking : AnthropicThinking?
  disable_parallel_tool_use : Bool?
  cache_control : AnthropicCacheControl?
  metadata : AnthropicMetadata?
  mcp_servers : Array[AnthropicMcpServer]
  container : AnthropicContainer?
  tool_streaming : Bool?
  effort : AnthropicEffort?
  task_budget : AnthropicTaskBudget?
  speed : AnthropicSpeed?
  inference_geo : AnthropicInferenceGeo?
  fallbacks : AnthropicFallbacks?
  anthropic_beta : Array[String]
  context_management : AnthropicContextManagement?
} derive(Debug, Eq)

///|
/// Construct typed Anthropic Messages provider options.
pub fn AnthropicLanguageModelOptions::new(
  send_reasoning? : Bool,
  structured_output_mode? : AnthropicStructuredOutputMode,
  thinking? : AnthropicThinking,
  disable_parallel_tool_use? : Bool,
  cache_control? : AnthropicCacheControl,
  metadata? : AnthropicMetadata,
  mcp_servers? : Array[AnthropicMcpServer] = [],
  container? : AnthropicContainer,
  tool_streaming? : Bool,
  effort? : AnthropicEffort,
  task_budget? : AnthropicTaskBudget,
  speed? : AnthropicSpeed,
  inference_geo? : AnthropicInferenceGeo,
  fallbacks? : AnthropicFallbacks,
  anthropic_beta? : Array[String] = [],
  context_management? : AnthropicContextManagement,
) -> AnthropicLanguageModelOptions {
  {
    send_reasoning,
    structured_output_mode,
    thinking,
    disable_parallel_tool_use,
    cache_control,
    metadata,
    mcp_servers: mcp_servers.copy(),
    container,
    tool_streaming,
    effort,
    task_budget,
    speed,
    inference_geo,
    fallbacks,
    anthropic_beta: anthropic_beta.copy(),
    context_management,
  }
}

///|
/// Convert typed Anthropic settings to a provider-options namespace.
pub fn AnthropicLanguageModelOptions::to_provider_options(
  self : AnthropicLanguageModelOptions,
  provider_name? : String = "anthropic",
) -> Map[String, Json] {
  anthropic_typed_namespace(
    provider_name,
    Map(
      [
        ..if self.send_reasoning is Some(value) {
          [("sendReasoning", Json::boolean(value))]
        },
        ..if self.structured_output_mode is Some(value) {
          [("structuredOutputMode", Json::string(value.wire_name()))]
        },
        ..if self.thinking is Some(value) {
          [("thinking", value.to_provider_json())]
        },
        ..if self.disable_parallel_tool_use is Some(value) {
          [("disableParallelToolUse", Json::boolean(value))]
        },
        ..if self.cache_control is Some(value) {
          [("cacheControl", value.to_json())]
        },
        ..if self.metadata is Some(value) {
          [("metadata", value.to_json())]
        },
        ..if self.mcp_servers.length() > 0 {
          [
            (
              "mcpServers",
              Json::array(
                [
                  for server in self.mcp_servers => server.to_json()
                ],
              ),
            ),
          ]
        },
        ..if self.container is Some(value) {
          [("container", value.to_json())]
        },
        ..if self.tool_streaming is Some(value) {
          [("toolStreaming", Json::boolean(value))]
        },
        ..if self.effort is Some(value) {
          [("effort", Json::string(value.wire_name()))]
        },
        ..if self.task_budget is Some(value) {
          [("taskBudget", value.to_json())]
        },
        ..if self.speed is Some(value) {
          [("speed", Json::string(value.wire_name()))]
        },
        ..if self.inference_geo is Some(value) {
          [("inferenceGeo", Json::string(value.wire_name()))]
        },
        ..if self.fallbacks is Some(value) {
          [("fallbacks", value.to_json())]
        },
        ..if self.anthropic_beta.length() > 0 {
          [("anthropicBeta", anthropic_string_array_json(self.anthropic_beta))]
        },
        ..if self.context_management is Some(value) {
          [("contextManagement", value.to_json())]
        },
      ],
    ),
  )
}

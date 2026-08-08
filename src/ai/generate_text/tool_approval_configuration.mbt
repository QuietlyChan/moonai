///|
/// Normalized approval decision for one tool call.
pub(all) enum ToolApprovalStatus {
  ToolApprovalNotApplicable
  ToolApprovalApproved(reason~ : String?)
  ToolApprovalDenied(reason~ : String?)
  ToolApprovalUserApproval
} derive(Debug, Eq)

///|
/// Mark a tool call as not requiring approval.
pub fn ToolApprovalStatus::not_applicable() -> ToolApprovalStatus {
  ToolApprovalNotApplicable
}

///|
/// Automatically approve a tool call.
pub fn ToolApprovalStatus::approved(reason? : String) -> ToolApprovalStatus {
  ToolApprovalApproved(reason~)
}

///|
/// Automatically deny a tool call.
pub fn ToolApprovalStatus::denied(reason? : String) -> ToolApprovalStatus {
  ToolApprovalDenied(reason~)
}

///|
/// Require an explicit user approval response.
pub fn ToolApprovalStatus::user_approval() -> ToolApprovalStatus {
  ToolApprovalUserApproval
}

///|
/// Options passed to a per-tool approval function.
pub(all) struct SingleToolApprovalOptions {
  tool_call_id : String
  messages : Array[@provider_utils.ModelMessage]
  tool_context : Json
  runtime_context : Json
}

///|
/// Resolve approval for one named tool after its input has been validated.
pub type SingleToolApprovalFunction = async (Json, SingleToolApprovalOptions) -> ToolApprovalStatus

///|
/// Options passed to a generic approval function.
pub(all) struct GenericToolApprovalOptions {
  tool_call : GenerateTextToolCall
  tools : @provider_utils.ToolSet
  tools_context : Map[String, Json]
  runtime_context : Json
  messages : Array[@provider_utils.ModelMessage]
}

///|
/// Resolve approval for any tool in a tool set.
pub type GenericToolApprovalFunction = async (GenericToolApprovalOptions) -> ToolApprovalStatus

///|
/// Static or input-dependent approval policy for a single tool.
pub(all) enum ToolApprovalRule {
  ToolApprovalRuleStatus(ToolApprovalStatus)
  ToolApprovalRuleFunction(SingleToolApprovalFunction)
}

///|
/// Construct a static per-tool approval rule.
pub fn ToolApprovalRule::status(value : ToolApprovalStatus) -> ToolApprovalRule {
  ToolApprovalRuleStatus(value)
}

///|
/// Construct an input-dependent per-tool approval rule.
pub fn ToolApprovalRule::when(
  resolve : SingleToolApprovalFunction,
) -> ToolApprovalRule {
  ToolApprovalRuleFunction(resolve)
}

///|
/// Generate-text approval configuration.
///
/// A generic function observes every valid registered call. A per-tool map
/// applies only to configured names. Either form takes precedence over a
/// tool's deprecated `needs_approval` setting.
pub(all) enum ToolApprovalConfiguration {
  ToolApprovalGeneric(GenericToolApprovalFunction)
  ToolApprovalPerTool(Map[String, ToolApprovalRule])
}

///|
/// Construct a generic approval configuration.
pub fn ToolApprovalConfiguration::generic(
  resolve : GenericToolApprovalFunction,
) -> ToolApprovalConfiguration {
  ToolApprovalGeneric(resolve)
}

///|
/// Construct a per-tool approval configuration.
pub fn ToolApprovalConfiguration::per_tool(
  rules : Map[String, ToolApprovalRule],
) -> ToolApprovalConfiguration {
  ToolApprovalPerTool(rules)
}

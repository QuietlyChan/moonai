///|
/// Cursor builtin tool kind, matching the ACP toolUseKind classification.
pub(all) enum CursorToolKind {
  Bash
  Edit
  Readonly
  Other
} derive(Debug, Eq)

///|
/// One entry of the Cursor CLI builtin tool catalog. Names, native ACP
/// projections, display titles, and kinds were captured from the official
/// Cursor CLI 2026.08.11 ACP implementation.
pub(all) struct CursorBuiltinTool {
  name : String
  native_name : String
  title : String
  kind : CursorToolKind
} derive(Debug, Eq)

///|
/// The Cursor builtin tool catalog (mcpToolCall is dynamic and
/// truncatedToolCall is a transport sentinel, so neither is exposed).
pub fn cursor_builtin_tools() -> Array[CursorBuiltinTool] {
  fn entry(
    name : String,
    native_name : String,
    title : String,
    kind : CursorToolKind,
  ) -> CursorBuiltinTool {
    { name, native_name, title, kind, }
  }

  [
    entry("bash", "shellToolCall", "Terminal", Bash),
    entry("delete", "deleteToolCall", "Delete", Edit),
    entry("glob", "globToolCall", "Find", Readonly),
    entry("grep", "grepToolCall", "grep", Readonly),
    entry("read", "readToolCall", "Read", Readonly),
    entry("updateTodos", "updateTodosToolCall", "Update TODOs", Other),
    entry("readTodos", "readTodosToolCall", "Read TODOs", Readonly),
    entry("edit", "editToolCall", "Edit", Edit),
    entry("ls", "lsToolCall", "List", Readonly),
    entry("readLints", "readLintsToolCall", "Read Lints", Readonly),
    entry("semanticSearch", "semSearchToolCall", "Codebase Search", Readonly),
    entry("createPlan", "createPlanToolCall", "Create Plan", Other),
    entry("webSearch", "webSearchToolCall", "Web Search", Readonly),
    entry("task", "taskToolCall", "Task", Other),
    entry(
      "listMcpResources",
      "listMcpResourcesToolCall",
      "List MCP Resources",
      Readonly,
    ),
    entry(
      "readMcpResource",
      "readMcpResourceToolCall",
      "Fetch MCP Resource",
      Readonly,
    ),
    entry("applyAgentDiff", "applyAgentDiffToolCall", "Apply Agent Diff", Edit),
    entry("fetch", "fetchToolCall", "Fetch", Readonly),
    entry("switchMode", "switchModeToolCall", "Switch Mode", Other),
    entry("generateImage", "generateImageToolCall", "Generate Image", Other),
    entry("recordScreen", "recordScreenToolCall", "Record Screen", Other),
    entry("computerUse", "computerUseToolCall", "Computer Use", Bash),
    entry("writeShellStdin", "writeShellStdinToolCall", "Write to stdin", Bash),
    entry("reflect", "reflectToolCall", "Reflect", Readonly),
    entry(
      "setupVmEnvironment",
      "setupVmEnvironmentToolCall",
      "Setup VM Environment",
      Bash,
    ),
    entry("replaceEnv", "replaceEnvToolCall", "Replace Environment", Bash),
    entry(
      "startGrindExecution",
      "startGrindExecutionToolCall",
      "Start Grind Execution",
      Bash,
    ),
    entry(
      "startGrindPlanning",
      "startGrindPlanningToolCall",
      "Start Grind Planning",
      Readonly,
    ),
    entry("webFetch", "webFetchToolCall", "Web Fetch", Readonly),
    entry(
      "reportBugfixResults",
      "reportBugfixResultsToolCall",
      "Report Bugfix Results",
      Other,
    ),
  ]
}

///|
/// Look up a builtin tool by its logical name.
pub fn cursor_builtin_tool(name~ : String) -> CursorBuiltinTool? {
  for tool in cursor_builtin_tools() {
    if tool.name == name {
      return Some(tool)
    }
  }
  None
}

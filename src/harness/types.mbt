///|
/// Harness V1 specification literal.
pub const HARNESS_V1_SPECIFICATION_VERSION : String = "harness-v1"

///|
/// Baseline permission mode for adapter-native built-in tools.
pub(all) enum HarnessV1PermissionMode {
  HarnessAllowReads
  HarnessAllowEdits
  HarnessAllowAll
} derive(Debug, Eq)

///|
/// Encode a permission mode for bridge messages.
pub fn HarnessV1PermissionMode::to_string(
  self : HarnessV1PermissionMode,
) -> String {
  match self {
    HarnessAllowReads => "allow-reads"
    HarnessAllowEdits => "allow-edits"
    HarnessAllowAll => "allow-all"
  }
}

///|
/// Decode a permission mode from bridge JSON.
pub fn HarnessV1PermissionMode::from_string(
  value : String,
) -> HarnessV1PermissionMode raise HarnessError {
  match value {
    "allow-reads" => HarnessAllowReads
    "allow-edits" => HarnessAllowEdits
    "allow-all" => HarnessAllowAll
    _ => raise harness_error("Invalid harness permission mode: " + value)
  }
}

///|
/// How a built-in tool is used by a coding agent.
pub(all) enum HarnessV1BuiltinToolUseKind {
  HarnessReadonlyTool
  HarnessEditTool
  HarnessBashTool
} derive(Debug, Eq)

///|
/// Cross-harness vocabulary for familiar runtime tools.
pub(all) enum HarnessV1BuiltinToolName {
  HarnessRead
  HarnessWrite
  HarnessEdit
  HarnessBash
  HarnessGrep
  HarnessGlob
  HarnessWebSearch
} derive(Debug, Eq)

///|
/// Return the wire spelling of a common built-in tool.
pub fn HarnessV1BuiltinToolName::to_string(
  self : HarnessV1BuiltinToolName,
) -> String {
  match self {
    HarnessRead => "read"
    HarnessWrite => "write"
    HarnessEdit => "edit"
    HarnessBash => "bash"
    HarnessGrep => "grep"
    HarnessGlob => "glob"
    HarnessWebSearch => "webSearch"
  }
}

///|
/// Common built-in tool names supported by the V1 contract.
pub let harness_v1_builtin_tool_names : Array[String] = [
  "read", "write", "edit", "bash", "grep", "glob", "webSearch",
]

///|
/// A native runtime tool plus cross-harness naming metadata.
pub(all) struct HarnessV1BuiltinTool {
  tool : @provider_utils.Tool
  native_name : String?
  common_name : HarnessV1BuiltinToolName?
  tool_use_kind : HarnessV1BuiltinToolUseKind?
}

///|
/// Declare an adapter-native tool without a cross-harness common name.
pub fn native_harness_tool(
  native_name~ : String,
  input_schema~ : Json,
  description? : String,
  tool_use_kind? : HarnessV1BuiltinToolUseKind,
) -> HarnessV1BuiltinTool {
  {
    tool: @provider_utils.Tool::function(input_schema, description?),
    native_name: Some(native_name),
    common_name: None,
    tool_use_kind,
  }
}

///|
/// AI SDK-style spelling for `native_harness_tool`.
pub fn nativeHarnessTool(
  native_name~ : String,
  input_schema~ : Json,
  description? : String,
  tool_use_kind? : HarnessV1BuiltinToolUseKind,
) -> HarnessV1BuiltinTool {
  native_harness_tool(native_name~, input_schema~, description?, tool_use_kind?)
}

///|
/// Name emitted by the bridge for a built-in tool.
pub fn HarnessV1BuiltinTool::wire_name(self : HarnessV1BuiltinTool) -> String? {
  match self.common_name {
    Some(value) => Some(value.to_string())
    None => self.native_name
  }
}

///|
/// Declare a runtime tool that maps to a common harness capability.
pub fn common_tool(
  common_name~ : HarnessV1BuiltinToolName,
  native_name~ : String,
  input_schema~ : Json,
  description? : String,
  tool_use_kind? : HarnessV1BuiltinToolUseKind,
) -> HarnessV1BuiltinTool {
  {
    tool: @provider_utils.Tool::function(input_schema, description?),
    native_name: Some(native_name),
    common_name: Some(common_name),
    tool_use_kind,
  }
}

///|
/// AI SDK-style spelling for `common_tool`.
pub fn commonTool(
  common_name~ : HarnessV1BuiltinToolName,
  native_name~ : String,
  input_schema~ : Json,
  description? : String,
  tool_use_kind? : HarnessV1BuiltinToolUseKind,
) -> HarnessV1BuiltinTool {
  common_tool(
    common_name~,
    native_name~,
    input_schema~,
    description?,
    tool_use_kind?,
  )
}

///|
/// A host-defined tool advertised to a harness runtime.
pub(all) struct HarnessV1ToolSpec {
  name : String
  description : String?
  input_schema : Json?
} derive(Debug, Eq)

///|
/// Construct a harness tool specification.
pub fn HarnessV1ToolSpec::new(
  name~ : String,
  description? : String,
  input_schema? : Json,
) -> HarnessV1ToolSpec {
  { name, description, input_schema }
}

///|
/// A single fresh prompt for a harness turn.
pub(all) enum HarnessV1Prompt {
  HarnessTextPrompt(String)
  HarnessUserMessage(@provider_utils.ModelMessage)
} derive(Debug, Eq)

///|
/// Construct a text prompt.
pub fn HarnessV1Prompt::text(value : String) -> HarnessV1Prompt {
  HarnessTextPrompt(value)
}

///|
/// Reduce a prompt to text, rejecting non-user model messages.
pub fn HarnessV1Prompt::to_text(
  self : HarnessV1Prompt,
) -> String raise HarnessCapabilityUnsupportedError {
  match self {
    HarnessTextPrompt(value) => value
    HarnessUserMessage(message) => {
      guard message.role == @provider_utils.ModelUser else {
        raise HarnessCapabilityUnsupportedError::new(
          message="Harness prompts must contain one user message",
        )
      }
      guard message.parts.length() > 0 else { return message.content }
      let text : Array[String] = []
      if message.content != "" {
        text.push(message.content)
      }
      for part in message.parts {
        text.push(harness_prompt_part_to_text(part))
      }
      text.join("\n\n")
    }
  }
}

///|
fn harness_prompt_part_to_text(
  part : @provider_utils.ModelContentPart,
) -> String raise HarnessCapabilityUnsupportedError {
  match part {
    @provider_utils.ModelText(value) => value
    @provider_utils.ModelPartProviderOptions(part~, ..) =>
      harness_prompt_part_to_text(part)
    _ =>
      raise HarnessCapabilityUnsupportedError::new(
        message="Harness prompts currently support text user parts only",
      )
  }
}

///|
/// One additional text file belonging to a harness skill.
pub(all) struct HarnessV1SkillFile {
  path : String
  content : String
} derive(Debug, Eq)

///|
/// A self-contained instruction bundle for a coding-agent runtime.
pub(all) struct HarnessV1Skill {
  name : String
  description : String
  content : String
  files : Array[HarnessV1SkillFile]
} derive(Debug, Eq)

///|
/// Construct a harness skill.
pub fn HarnessV1Skill::new(
  name~ : String,
  description~ : String,
  content~ : String,
  files? : Array[HarnessV1SkillFile] = [],
) -> HarnessV1Skill {
  { name, description, content, files }
}

///|
/// One file included in an adapter bootstrap recipe.
pub(all) struct HarnessV1BootstrapFile {
  path : String
  content : String
} derive(Debug, Eq)

///|
/// One sequential command in an adapter bootstrap recipe.
pub(all) struct HarnessV1BootstrapCommand {
  command : String
  working_directory : String?
} derive(Debug, Eq)

///|
/// Files and commands needed to install a harness bridge.
pub(all) struct HarnessV1Bootstrap {
  harness_id : String
  bootstrap_dir : String
  files : Array[HarnessV1BootstrapFile]
  commands : Array[HarnessV1BootstrapCommand]
} derive(Debug, Eq)

///|
/// Stable identity of a bootstrap recipe.
pub fn HarnessV1Bootstrap::identity(self : HarnessV1Bootstrap) -> String {
  let files = [
    for file in self.files => {
      ({ "path": file.path, "content": file.content } : Json)
    }
  ]
  let commands = [
    for command in self.commands => {
      let fields : Map[String, Json] = Map([
        ("command", Json::string(command.command)),
      ])
      if command.working_directory is Some(value) {
        fields["workingDirectory"] = Json::string(value)
      }
      Json::object(fields)
    }
  ]
  let digest = @mooncry.sha256(
    @utf8.encode(
      (
        {
          "harnessId": self.harness_id,
          "bootstrapDir": self.bootstrap_dir,
          "files": files,
          "commands": commands,
        } : Json).stringify(),
    ),
  )
  @base64.encode(digest, padding=false)
}

///|
/// Adapter-native built-in tool filtering policy.
pub(all) enum HarnessV1BuiltinToolFiltering {
  HarnessAllowTools(Array[String])
  HarnessDenyTools(Array[String])
} derive(Debug, Eq)

///|
/// Whether a built-in tool remains active under the filtering policy.
pub fn is_harness_v1_builtin_tool_included(
  tool_name : String,
  tool_filtering : HarnessV1BuiltinToolFiltering?,
) -> Bool {
  match tool_filtering {
    None => true
    Some(HarnessAllowTools(names)) => names.contains(tool_name)
    Some(HarnessDenyTools(names)) => !names.contains(tool_name)
  }
}

///|
/// AI SDK-style spelling for `is_harness_v1_builtin_tool_included`.
pub fn isHarnessV1BuiltinToolIncluded(
  tool_name : String,
  tool_filtering : HarnessV1BuiltinToolFiltering?,
) -> Bool {
  is_harness_v1_builtin_tool_included(tool_name, tool_filtering)
}

///|
/// Explain why a built-in tool is inactive.
pub fn get_harness_v1_builtin_tool_filtering_denial_reason(
  tool_name : String,
) -> String {
  "Tool '" +
  tool_name +
  "' is inactive due to the HarnessAgent tool filtering policy."
}

///|
/// AI SDK-style spelling for the filtering denial reason.
pub fn getHarnessV1BuiltinToolFilteringDenialReason(
  tool_name : String,
) -> String {
  get_harness_v1_builtin_tool_filtering_denial_reason(tool_name)
}

///|
/// Non-fatal warning emitted by a harness call.
pub(all) enum HarnessV1CallWarning {
  HarnessUnsupportedSetting(setting~ : String, details~ : String?)
  HarnessUnsupportedTool(tool~ : String, details~ : String?)
  HarnessOtherWarning(message~ : String)
} derive(Debug, Eq)

///|
/// Adapter-namespaced metadata attached to stream parts.
pub type HarnessV1Metadata = Map[String, Json]

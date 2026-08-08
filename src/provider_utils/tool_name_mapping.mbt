///|
/// Bidirectional mapping between caller-visible tool names and the fixed names
/// used by provider protocols.
///
/// Provider-defined tools can be installed under an application-specific name.
/// Function tools are intentionally left unchanged.
pub struct ToolNameMapping {
  priv custom_to_provider : Map[String, String]
  priv provider_to_custom : Map[String, String]
}

///|
/// Construct an identity tool-name mapping.
pub fn ToolNameMapping::identity() -> ToolNameMapping {
  { custom_to_provider: Map([]), provider_to_custom: Map([]) }
}

///|
/// Map a caller-visible name to the provider protocol name.
pub fn ToolNameMapping::to_provider_tool_name(
  self : ToolNameMapping,
  custom_tool_name : String,
) -> String {
  self.custom_to_provider.get(custom_tool_name).unwrap_or(custom_tool_name)
}

///|
/// AI SDK-style spelling for `to_provider_tool_name`.
pub fn ToolNameMapping::toProviderToolName(
  self : ToolNameMapping,
  custom_tool_name : String,
) -> String {
  self.to_provider_tool_name(custom_tool_name)
}

///|
/// Map a provider protocol name back to the caller-visible name.
pub fn ToolNameMapping::to_custom_tool_name(
  self : ToolNameMapping,
  provider_tool_name : String,
) -> String {
  self.provider_to_custom.get(provider_tool_name).unwrap_or(provider_tool_name)
}

///|
/// AI SDK-style spelling for `to_custom_tool_name`.
pub fn ToolNameMapping::toCustomToolName(
  self : ToolNameMapping,
  provider_tool_name : String,
) -> String {
  self.to_custom_tool_name(provider_tool_name)
}

///|
/// Build the name mapping for one model call.
///
/// `provider_tool_names` maps stable provider-tool IDs such as
/// `openai.code_interpreter` to their protocol names such as
/// `code_interpreter`.
pub fn create_tool_name_mapping(
  tools : Array[@provider.ToolDefinition],
  provider_tool_names : Map[String, String],
) -> ToolNameMapping {
  let mapping = ToolNameMapping::identity()
  for tool in tools {
    match tool {
      @provider.ProviderTool(id~, name~, ..) =>
        if provider_tool_names.get(id) is Some(provider_tool_name) {
          mapping.custom_to_provider[name] = provider_tool_name
          mapping.provider_to_custom[provider_tool_name] = name
        }
      @provider.FunctionTool(..) => ()
    }
  }
  mapping
}

///|
/// AI SDK-style spelling for `create_tool_name_mapping`.
pub fn createToolNameMapping(
  tools : Array[@provider.ToolDefinition],
  provider_tool_names : Map[String, String],
) -> ToolNameMapping {
  create_tool_name_mapping(tools, provider_tool_names)
}

///|
/// Build a tool-name mapping directly from V4 language-model tools.
///
/// V4 provider implementations should use this form so the versioned
/// contract does not need to be lowered to `ToolDefinition` merely to map
/// provider-defined names.
pub fn create_v4_tool_name_mapping(
  tools : Array[@provider.LanguageModelV4Tool],
  provider_tool_names : Map[String, String],
) -> ToolNameMapping {
  let mapping = ToolNameMapping::identity()
  for tool in tools {
    match tool {
      @provider.LanguageModelV4Tool::V4ProviderTool(value) =>
        if provider_tool_names.get(value.id) is Some(provider_tool_name) {
          mapping.custom_to_provider[value.name] = provider_tool_name
          mapping.provider_to_custom[provider_tool_name] = value.name
        }
      @provider.LanguageModelV4Tool::V4FunctionTool(_) => ()
    }
  }
  mapping
}

///|
/// AI SDK-style spelling for `create_v4_tool_name_mapping`.
pub fn createV4ToolNameMapping(
  tools : Array[@provider.LanguageModelV4Tool],
  provider_tool_names : Map[String, String],
) -> ToolNameMapping {
  create_v4_tool_name_mapping(tools, provider_tool_names)
}

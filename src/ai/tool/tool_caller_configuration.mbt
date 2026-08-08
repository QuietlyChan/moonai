///|
/// One permitted route to a high-level tool.
pub(all) enum ToolCallerReference {
  DirectToolCaller
  NamedToolCaller(String)
} derive(Debug, Eq)

///|
/// Construct a direct model-to-tool route.
pub fn ToolCallerReference::direct() -> ToolCallerReference {
  DirectToolCaller
}

///|
/// Construct a route through a named caller tool.
pub fn ToolCallerReference::tool(name : String) -> ToolCallerReference {
  NamedToolCaller(name)
}

///|
/// User-facing caller routes keyed by callee tool name.
pub type ToolCallerConfiguration = Map[String, Array[ToolCallerReference]]

///|
/// Validated caller routes used while preparing each model step.
pub type ResolvedToolCallers = Map[String, Array[ToolCallerReference]]

///|
/// Tool sets prepared for model visibility and local execution.
pub struct PreparedToolsForToolCallers {
  priv execution_tools_value : @provider_utils.ToolSet
  priv model_tools_value : @provider_utils.ToolSet
}

///|
/// Return the tools available to high-level execution and parsing.
pub fn PreparedToolsForToolCallers::execution_tools(
  self : PreparedToolsForToolCallers,
) -> @provider_utils.ToolSet {
  @provider_utils.copy_tool_set(self.execution_tools_value)
}

///|
/// Return the tools advertised to the language model.
pub fn PreparedToolsForToolCallers::model_tools(
  self : PreparedToolsForToolCallers,
) -> @provider_utils.ToolSet {
  @provider_utils.copy_tool_set(self.model_tools_value)
}

///|
fn copy_tool_caller_references(
  references : Array[ToolCallerReference],
) -> Array[ToolCallerReference] {
  references.copy()
}

///|
/// Validate and freeze caller routing before any model step starts.
///
/// MoonBit uses explicit named references instead of TypeScript's opaque
/// object references. The validation provides the same runtime guarantees:
/// every callee exists and every named caller is a registered caller tool.
pub fn resolve_tool_caller_configuration(
  tools : @provider_utils.ToolSet,
  configuration : ToolCallerConfiguration?,
) -> ResolvedToolCallers? raise @provider.InvalidArgumentError {
  guard configuration is Some(configuration) else { return None }
  let resolved : ResolvedToolCallers = Map([])
  for entry in configuration.iter2() {
    let (tool_name, callers) = entry
    guard tools.get(tool_name) is Some(_) else {
      raise @provider.InvalidArgumentError(
        argument="experimental_tool_callers",
        message="unknown tool \"\{tool_name}\".",
      )
    }
    for caller in callers {
      match caller {
        DirectToolCaller => ()
        NamedToolCaller(caller_name) => {
          let caller_tool = match tools.get(caller_name) {
            Some(tool) => tool
            None =>
              raise @provider.InvalidArgumentError(
                argument="experimental_tool_callers",
                message="tool \"\{tool_name}\" contains unknown caller \"\{caller_name}\".",
              )
          }
          guard @provider_utils.experimental_get_tool_caller(caller_tool)
            is Some(_) else {
            raise @provider.InvalidArgumentError(
              argument="experimental_tool_callers",
              message="tool \"\{caller_name}\" is not registered as a tool caller.",
            )
          }
        }
      }
    }
    resolved[tool_name] = copy_tool_caller_references(callers)
  }
  Some(resolved)
}

///|
/// AI SDK-style camel-case spelling.
pub fn resolveToolCallerConfiguration(
  tools : @provider_utils.ToolSet,
  configuration : ToolCallerConfiguration?,
) -> ResolvedToolCallers? raise @provider.InvalidArgumentError {
  resolve_tool_caller_configuration(tools, configuration)
}

///|
fn configured_tool_visible_to_model(
  configured : Map[String, Bool],
  tool_name : String,
) -> Bool {
  match configured.get(tool_name) {
    Some(value) => value
    None => true
  }
}

///|
/// Prepare execution and model-visible tools for caller routing.
///
/// Provider callers add their provider options to the callee and keep it
/// model-visible. Local-only callees are hidden from the model and late-bound
/// into their caller's execution callback.
pub fn prepare_tools_for_tool_callers(
  tools : @provider_utils.ToolSet,
  tool_callers : ResolvedToolCallers?,
) -> PreparedToolsForToolCallers {
  guard tool_callers is Some(tool_callers) else {
    return {
      execution_tools_value: @provider_utils.copy_tool_set(tools),
      model_tools_value: @provider_utils.copy_tool_set(tools),
    }
  }
  let execution_tools = @provider_utils.copy_tool_set(tools)
  let local_tools_by_caller : Map[String, @provider_utils.ToolSet] = Map([])
  let model_visibility : Map[String, Bool] = Map([])
  for entry in tool_callers.iter2() {
    let (tool_name, caller_names) = entry
    let mut prepared_tool = match execution_tools.get(tool_name) {
      Some(tool) => tool
      None => continue
    }
    let mut available_directly = false
    let mut available_to_provider = false
    for caller_name in caller_names {
      match caller_name {
        DirectToolCaller => available_directly = true
        NamedToolCaller(name) => {
          let caller = match execution_tools.get(name) {
            Some(tool) => @provider_utils.experimental_get_tool_caller(tool)
            None => None
          }
          match caller {
            Some(@provider_utils.ProviderToolCaller(_)) => {
              available_to_provider = true
              prepared_tool = prepared_tool.with_provider_options(
                caller
                .unwrap()
                .prepare_provider_options(prepared_tool.provider_options()),
              )
            }
            Some(@provider_utils.LocalToolCaller(_)) => {
              let local_tools = match local_tools_by_caller.get(name) {
                Some(values) => values
                None => Map([])
              }
              local_tools[tool_name] = prepared_tool
              local_tools_by_caller[name] = local_tools
            }
            None => ()
          }
        }
      }
    }
    execution_tools[tool_name] = prepared_tool
    model_visibility[tool_name] = available_directly || available_to_provider
  }
  let model_tools : @provider_utils.ToolSet = Map([])
  for entry in execution_tools.iter2() {
    if configured_tool_visible_to_model(model_visibility, entry.0) {
      model_tools[entry.0] = entry.1
    }
  }
  let caller_entries = [ for entry in execution_tools.iter2() => entry ]
  for entry in caller_entries {
    let (caller_name, caller_tool) = entry
    match @provider_utils.experimental_get_tool_caller(caller_tool) {
      Some(@provider_utils.LocalToolCaller(_)) as caller => {
        let bound = caller
          .unwrap()
          .bind(
            match local_tools_by_caller.get(caller_name) {
              Some(values) => values
              None => Map([])
            },
          )
        if bound is Some(bound_tool) {
          execution_tools[caller_name] = bound_tool
          if model_tools.get(caller_name) is Some(_) {
            model_tools[caller_name] = bound_tool
          }
        }
      }
      _ => ()
    }
  }
  { execution_tools_value: execution_tools, model_tools_value: model_tools }
}

///|
/// AI SDK-style camel-case spelling.
pub fn prepareToolsForToolCallers(
  tools : @provider_utils.ToolSet,
  tool_callers : ResolvedToolCallers?,
) -> PreparedToolsForToolCallers {
  prepare_tools_for_tool_callers(tools, tool_callers)
}

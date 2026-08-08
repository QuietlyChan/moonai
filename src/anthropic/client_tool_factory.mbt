///|
/// Lift an Anthropic provider-defined protocol into an application-executed
/// high-level tool while preserving the shared AI SDK behavior hooks.
fn anthropic_client_tool(
  id : String,
  input_schema : Json,
  args : Json,
  output_schema : Json?,
  execute : @provider_utils.ToolExecuteFunction?,
  needs_approval : @provider_utils.ToolNeedsApproval?,
  to_model_output : @provider_utils.ToolModelOutputFunction?,
  on_input_start : @provider_utils.ToolInputStartFunction?,
  on_input_delta : @provider_utils.ToolInputDeltaFunction?,
  on_input_available : @provider_utils.ToolInputAvailableFunction?,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_defined_tool_factory(id~, input_schema~).create(
    args~,
    output_schema?,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

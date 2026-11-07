///|
fn anthropic_bash_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "command": { "type": "string" },
      "restart": { "type": "boolean" },
    },
    "required": ["command"],
    "additionalProperties": false,
  }
}

///|
/// AI SDK's default Anthropic bash executor delegates to the sandbox attached
/// to the current tool execution context.
async fn anthropic_default_bash_execute(
  input : Json,
  options : @provider_utils.ToolExecutionOptions,
) -> Json {
  let command = @provider_utils.json_string_field(input, "command").unwrap_or_else(() => {
      fail("Anthropic bash input requires command")
    },
  )
  let sandbox = options.experimental_sandbox.unwrap_or_else(() => {
    fail("Sandbox session is not available")
  })
  @provider.check_cancellation(options.cancellation_token)
  sandbox
  .run(
    @provider_utils.SandboxProcessOptions::new(
      command~,
      cancellation_token?=options.cancellation_token,
    ),
  )
  .to_json()
}

///|
/// Create Anthropic's 2024-10-22 application-executed bash tool.
pub fn bash_20241022(
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  disable_default_execute? : Bool = false,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let executor = match execute {
    Some(value) => Some(value)
    None if disable_default_execute => None
    None => Some(anthropic_default_bash_execute)
  }
  anthropic_client_tool(
    "anthropic.bash_20241022",
    anthropic_bash_input_schema(),
    Json::empty_object(),
    output_schema,
    executor,
    needs_approval,
    to_model_output,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// Create Anthropic's 2025-01-24 application-executed bash tool.
pub fn bash_20250124(
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  disable_default_execute? : Bool = false,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let executor = match execute {
    Some(value) => Some(value)
    None if disable_default_execute => None
    None => Some(anthropic_default_bash_execute)
  }
  anthropic_client_tool(
    "anthropic.bash_20250124",
    anthropic_bash_input_schema(),
    Json::empty_object(),
    output_schema,
    executor,
    needs_approval,
    to_model_output,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

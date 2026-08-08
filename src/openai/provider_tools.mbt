///|
/// OpenAI-specific high-level tool factories.
///
/// The value is stateless. It mirrors AI SDK's `openai.tools` namespace while
/// keeping provider transport definitions separate from application behavior.
pub struct OpenAITools {}

///|
/// Return the shared OpenAI tool-factory namespace.
fn openai_tools() -> OpenAITools {
  OpenAITools::{  }
}

///|
/// Select OpenAI-specific tools from a provider factory.
pub fn OpenAIProvider::tools(_self : OpenAIProvider) -> OpenAITools {
  openai_tools()
}

///|
/// Create the application-executed OpenAI apply-patch tool.
pub fn OpenAITools::apply_patch(
  _self : OpenAITools,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_defined_tool_factory_with_output_schema(
    id="openai.apply_patch",
    input_schema=openai_apply_patch_input_schema(),
    output_schema=openai_apply_patch_output_schema(),
  ).create(
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// AI SDK-style camel-case spelling for `apply_patch`.
pub fn OpenAITools::applyPatch(
  self : OpenAITools,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.apply_patch(
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create an application-executed OpenAI custom tool.
pub fn OpenAITools::custom_tool(
  _self : OpenAITools,
  options? : OpenAICustomToolOptions,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args = match options {
    Some(value) => value.to_args_json()
    None => Json::empty_object()
  }
  @provider_utils.create_provider_defined_tool_factory(id="openai.custom", input_schema={
    "type": "string",
  }).create(
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

///|
/// AI SDK-style camel-case spelling for `custom_tool`.
pub fn OpenAITools::customTool(
  self : OpenAITools,
  options? : OpenAICustomToolOptions,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.custom_tool(
    options?,
    output_schema?,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the provider-executed OpenAI Code Interpreter tool.
pub fn OpenAITools::code_interpreter(
  _self : OpenAITools,
  container? : OpenAICodeInterpreterContainer,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args : Json = match container {
    Some(value) => { "container": value.to_args_json() }
    None => Json::empty_object()
  }
  @provider_utils.create_provider_executed_tool_factory(
    id="openai.code_interpreter",
    input_schema=openai_code_interpreter_input_schema(),
    output_schema=openai_code_interpreter_output_schema(),
  ).create(args~, on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// AI SDK-style camel-case spelling for `code_interpreter`.
pub fn OpenAITools::codeInterpreter(
  self : OpenAITools,
  container? : OpenAICodeInterpreterContainer,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.code_interpreter(
    container?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the application-executed OpenAI computer-use tool.
pub fn OpenAITools::computer(
  _self : OpenAITools,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_defined_tool_factory_with_output_schema(
    id="openai.computer",
    input_schema=openai_computer_input_schema(),
    output_schema=openai_computer_output_schema(),
  ).create(
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the provider-executed OpenAI file-search tool.
pub fn OpenAITools::file_search(
  _self : OpenAITools,
  options : OpenAIFileSearchOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_executed_tool_factory(
    id="openai.file_search",
    input_schema=openai_empty_object_schema(),
    output_schema=openai_file_search_output_schema(),
  ).create(
    args=options.to_args_json(),
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// AI SDK-style camel-case spelling for `file_search`.
pub fn OpenAITools::fileSearch(
  self : OpenAITools,
  options : OpenAIFileSearchOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.file_search(
    options,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the provider-executed OpenAI image-generation tool.
pub fn OpenAITools::image_generation(
  _self : OpenAITools,
  options? : OpenAIImageGenerationOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args = match options {
    Some(value) => value.to_args_json()
    None => Json::empty_object()
  }
  @provider_utils.create_provider_executed_tool_factory(
    id="openai.image_generation",
    input_schema=openai_empty_object_schema(),
    output_schema=openai_image_generation_output_schema(),
  ).create(args~, on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// AI SDK-style camel-case spelling for `image_generation`.
pub fn OpenAITools::imageGeneration(
  self : OpenAITools,
  options? : OpenAIImageGenerationOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.image_generation(
    options?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the application-executed OpenAI local-shell tool.
pub fn OpenAITools::local_shell(
  _self : OpenAITools,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_defined_tool_factory_with_output_schema(
    id="openai.local_shell",
    input_schema=openai_local_shell_input_schema(),
    output_schema=openai_local_shell_output_schema(),
  ).create(
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// AI SDK-style camel-case spelling for `local_shell`.
pub fn OpenAITools::localShell(
  self : OpenAITools,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.local_shell(
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the application-executed OpenAI shell tool.
pub fn OpenAITools::shell(
  _self : OpenAITools,
  environment? : OpenAIShellEnvironment,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args : Json = match environment {
    Some(value) => { "environment": value.to_args_json() }
    None => Json::empty_object()
  }
  @provider_utils.create_provider_defined_tool_factory_with_output_schema(
    id="openai.shell",
    input_schema=openai_shell_input_schema(),
    output_schema=openai_shell_output_schema(),
  ).create(
    args~,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the provider-executed preview OpenAI web-search tool.
pub fn OpenAITools::web_search_preview(
  _self : OpenAITools,
  options? : OpenAIWebSearchPreviewOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args = match options {
    Some(value) => value.to_args_json()
    None => Json::empty_object()
  }
  @provider_utils.create_provider_executed_tool_factory(
    id="openai.web_search_preview",
    input_schema=openai_empty_object_schema(),
    output_schema=openai_web_search_preview_output_schema(),
  ).create(args~, on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// AI SDK-style camel-case spelling for `web_search_preview`.
pub fn OpenAITools::webSearchPreview(
  self : OpenAITools,
  options? : OpenAIWebSearchPreviewOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.web_search_preview(
    options?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the provider-executed current OpenAI web-search tool.
pub fn OpenAITools::web_search(
  _self : OpenAITools,
  options? : OpenAIWebSearchOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args = match options {
    Some(value) => value.to_args_json()
    None => Json::empty_object()
  }
  @provider_utils.create_provider_executed_tool_factory(
    id="openai.web_search",
    input_schema=openai_empty_object_schema(),
    output_schema=openai_web_search_output_schema(),
  ).create(args~, on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// AI SDK-style camel-case spelling for `web_search`.
pub fn OpenAITools::webSearch(
  self : OpenAITools,
  options? : OpenAIWebSearchOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.web_search(
    options?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the provider-executed OpenAI MCP tool.
pub fn OpenAITools::mcp(
  _self : OpenAITools,
  options : OpenAIMCPOptions,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_executed_tool_factory(
    id="openai.mcp",
    input_schema=openai_empty_object_schema(),
    output_schema=openai_mcp_output_schema(),
  ).create(
    args=options.to_args_json(),
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create the OpenAI provider-executed programmatic caller tool.
pub fn OpenAITools::programmatic_tool_calling(
  _self : OpenAITools,
) -> @provider_utils.Tool {
  programmatic_tool_calling()
}

///|
/// AI SDK-style camel-case spelling for `programmatic_tool_calling`.
pub fn OpenAITools::programmaticToolCalling(
  self : OpenAITools,
) -> @provider_utils.Tool {
  self.programmatic_tool_calling()
}

///|
/// Create the application-executed OpenAI tool-search tool.
pub fn OpenAITools::tool_search(
  _self : OpenAITools,
  options? : OpenAIToolSearchOptions,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args = match options {
    Some(value) => value.to_args_json()
    None => Json::empty_object()
  }
  @provider_utils.create_provider_defined_tool_factory_with_output_schema(
    id="openai.tool_search",
    input_schema=openai_tool_search_input_schema(),
    output_schema=openai_tool_search_output_schema(),
  ).create(
    args~,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// AI SDK-style camel-case spelling for `tool_search`.
pub fn OpenAITools::toolSearch(
  self : OpenAITools,
  options? : OpenAIToolSearchOptions,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  self.tool_search(
    options?,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

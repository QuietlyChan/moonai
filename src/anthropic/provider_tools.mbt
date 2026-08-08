///|
/// Anthropic-specific high-level tool factories.
///
/// The value is stateless and mirrors AI SDK's `anthropic.tools` namespace.
pub struct AnthropicTools {}

///|
/// Return the shared Anthropic tool-factory namespace.
pub fn anthropic_tools() -> AnthropicTools {
  AnthropicTools::{  }
}

///|
/// AI SDK-style camel-case spelling for `anthropic_tools`.
pub fn anthropicTools() -> AnthropicTools {
  anthropic_tools()
}

///|
/// Select Anthropic-specific tools from a provider factory.
pub fn AnthropicProvider::tools(_self : AnthropicProvider) -> AnthropicTools {
  anthropic_tools()
}

///|
/// Create Anthropic's advisor tool.
pub fn AnthropicTools::advisor_20260301(
  _self : AnthropicTools,
  model~ : String,
  max_uses? : Int,
  caching? : AnthropicAdvisorCaching,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  advisor_20260301(
    model~,
    max_uses?,
    caching?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's 2024-10-22 bash tool.
pub fn AnthropicTools::bash_20241022(
  _self : AnthropicTools,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  disable_default_execute? : Bool = false,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  bash_20241022(
    output_schema?,
    execute?,
    disable_default_execute~,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's 2025-01-24 bash tool.
pub fn AnthropicTools::bash_20250124(
  _self : AnthropicTools,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  disable_default_execute? : Bool = false,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  bash_20250124(
    output_schema?,
    execute?,
    disable_default_execute~,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's 2025-05-22 provider-executed code tool.
pub fn AnthropicTools::codeExecution_20250522(
  _self : AnthropicTools,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  code_execution_20250522(on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// Create Anthropic's 2025-08-25 provider-executed code tool.
pub fn AnthropicTools::codeExecution_20250825(
  _self : AnthropicTools,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  code_execution_20250825(on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// Create Anthropic's current provider-executed code tool.
pub fn AnthropicTools::codeExecution_20260120(
  _self : AnthropicTools,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  code_execution_20260120(on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// Create Anthropic's 2024-10-22 computer tool.
pub fn AnthropicTools::computer_20241022(
  _self : AnthropicTools,
  display_width_px~ : Int,
  display_height_px~ : Int,
  display_number? : Int,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  computer_20241022(
    display_width_px~,
    display_height_px~,
    display_number?,
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
/// Create Anthropic's 2025-01-24 computer tool.
pub fn AnthropicTools::computer_20250124(
  _self : AnthropicTools,
  display_width_px~ : Int,
  display_height_px~ : Int,
  display_number? : Int,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  computer_20250124(
    display_width_px~,
    display_height_px~,
    display_number?,
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
/// Create Anthropic's current computer tool.
pub fn AnthropicTools::computer_20251124(
  _self : AnthropicTools,
  display_width_px~ : Int,
  display_height_px~ : Int,
  display_number? : Int,
  enable_zoom? : Bool,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  computer_20251124(
    display_width_px~,
    display_height_px~,
    display_number?,
    enable_zoom?,
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
/// Create Anthropic's application-executed memory tool.
pub fn AnthropicTools::memory_20250818(
  _self : AnthropicTools,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  memory_20250818(
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
/// Create Anthropic's 2024-10-22 text-editor tool.
pub fn AnthropicTools::textEditor_20241022(
  _self : AnthropicTools,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  text_editor_20241022(
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
/// Create Anthropic's 2025-01-24 text-editor tool.
pub fn AnthropicTools::textEditor_20250124(
  _self : AnthropicTools,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  text_editor_20250124(
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
/// Create Anthropic's 2025-04-29 text-editor tool.
pub fn AnthropicTools::textEditor_20250429(
  _self : AnthropicTools,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  text_editor_20250429(
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
/// Create Anthropic's current text-editor tool.
pub fn AnthropicTools::textEditor_20250728(
  _self : AnthropicTools,
  max_characters? : Int,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  text_editor_20250728(
    max_characters?,
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
/// Create Anthropic's 2025-09-10 web-fetch tool.
pub fn AnthropicTools::webFetch_20250910(
  _self : AnthropicTools,
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  citations? : AnthropicWebFetchCitations,
  max_content_tokens? : Int,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_fetch_20250910(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    citations?,
    max_content_tokens?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's current web-fetch tool.
pub fn AnthropicTools::webFetch_20260209(
  _self : AnthropicTools,
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  citations? : AnthropicWebFetchCitations,
  max_content_tokens? : Int,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_fetch_20260209(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    citations?,
    max_content_tokens?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's 2025-03-05 web-search tool.
pub fn AnthropicTools::webSearch_20250305(
  _self : AnthropicTools,
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  user_location? : AnthropicWebSearchUserLocation,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_search_20250305(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    user_location?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's current web-search tool.
pub fn AnthropicTools::webSearch_20260209(
  _self : AnthropicTools,
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  user_location? : AnthropicWebSearchUserLocation,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_search_20260209(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    user_location?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's regex tool-search tool.
pub fn AnthropicTools::toolSearchRegex_20251119(
  _self : AnthropicTools,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  tool_search_regex_20251119(
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's BM25 tool-search tool.
pub fn AnthropicTools::toolSearchBm25_20251119(
  _self : AnthropicTools,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  tool_search_bm25_20251119(
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

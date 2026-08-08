///|
fn anthropic_text_editor_input_schema(include_undo : Bool) -> Json {
  let commands : Array[Json] = ["view", "create", "str_replace", "insert"]
  if include_undo {
    commands.push("undo_edit")
  }
  {
    "type": "object",
    "properties": {
      "command": { "type": "string", "enum": commands },
      "path": { "type": "string" },
      "file_text": { "type": "string" },
      "insert_line": { "type": "integer" },
      "new_str": { "type": "string" },
      "insert_text": { "type": "string" },
      "old_str": { "type": "string" },
      "view_range": { "type": "array", "items": { "type": "integer" } },
    },
    "required": ["command", "path"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_text_editor_tool(
  id : String,
  include_undo : Bool,
  args : Json,
  output_schema : Json?,
  execute : @provider_utils.ToolExecuteFunction?,
  needs_approval : @provider_utils.ToolNeedsApproval?,
  to_model_output : @provider_utils.ToolModelOutputFunction?,
  on_input_start : @provider_utils.ToolInputStartFunction?,
  on_input_delta : @provider_utils.ToolInputDeltaFunction?,
  on_input_available : @provider_utils.ToolInputAvailableFunction?,
) -> @provider_utils.Tool {
  anthropic_client_tool(
    id,
    anthropic_text_editor_input_schema(include_undo),
    args,
    output_schema,
    execute,
    needs_approval,
    to_model_output,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// Create Anthropic's 2024-10-22 application-executed text editor.
pub fn text_editor_20241022(
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_text_editor_tool(
    "anthropic.text_editor_20241022",
    true,
    Json::empty_object(),
    output_schema,
    execute,
    needs_approval,
    to_model_output,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn textEditor_20241022(
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
/// Create Anthropic's 2025-01-24 application-executed text editor.
pub fn text_editor_20250124(
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_text_editor_tool(
    "anthropic.text_editor_20250124",
    true,
    Json::empty_object(),
    output_schema,
    execute,
    needs_approval,
    to_model_output,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn textEditor_20250124(
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
/// Create Anthropic's 2025-04-29 application-executed text editor.
pub fn text_editor_20250429(
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_text_editor_tool(
    "anthropic.text_editor_20250429",
    false,
    Json::empty_object(),
    output_schema,
    execute,
    needs_approval,
    to_model_output,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn textEditor_20250429(
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
/// Create Anthropic's current application-executed text editor.
pub fn text_editor_20250728(
  max_characters? : Int,
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args : Json = match max_characters {
    Some(value) => { "maxCharacters": value }
    None => Json::empty_object()
  }
  anthropic_text_editor_tool(
    "anthropic.text_editor_20250728", false, args, output_schema, execute, needs_approval,
    to_model_output, on_input_start, on_input_delta, on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn textEditor_20250728(
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

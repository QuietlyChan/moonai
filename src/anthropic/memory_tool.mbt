///|
fn anthropic_memory_20250818_input_schema() -> Json {
  {
    "oneOf": [
      {
        "type": "object",
        "properties": {
          "command": { "const": "view" },
          "path": { "type": "string" },
          "view_range": {
            "type": "array",
            "items": { "type": "number" },
            "minItems": 2,
            "maxItems": 2,
          },
        },
        "required": ["command", "path"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "command": { "const": "create" },
          "path": { "type": "string" },
          "file_text": { "type": "string" },
        },
        "required": ["command", "path", "file_text"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "command": { "const": "str_replace" },
          "path": { "type": "string" },
          "old_str": { "type": "string" },
          "new_str": { "type": "string" },
        },
        "required": ["command", "path", "old_str", "new_str"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "command": { "const": "insert" },
          "path": { "type": "string" },
          "insert_line": { "type": "number" },
          "insert_text": { "type": "string" },
        },
        "required": ["command", "path", "insert_line", "insert_text"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "command": { "const": "delete" },
          "path": { "type": "string" },
        },
        "required": ["command", "path"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "command": { "const": "rename" },
          "old_path": { "type": "string" },
          "new_path": { "type": "string" },
        },
        "required": ["command", "old_path", "new_path"],
        "additionalProperties": false,
      },
    ],
  }
}

///|
/// Create Anthropic's application-executed memory tool.
pub fn memory_20250818(
  output_schema? : Json,
  execute? : @provider_utils.ToolExecuteFunction,
  needs_approval? : @provider_utils.ToolNeedsApproval,
  to_model_output? : @provider_utils.ToolModelOutputFunction,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_client_tool(
    "anthropic.memory_20250818",
    anthropic_memory_20250818_input_schema(),
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

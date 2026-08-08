///|
fn anthropic_code_execution_file_content_schema(kind : String) -> Json {
  {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "type": { "const": kind },
        "file_id": { "type": "string" },
      },
      "required": ["type", "file_id"],
      "additionalProperties": false,
    },
  }
}

///|
fn anthropic_code_execution_result_schema(encrypted : Bool) -> Json {
  let properties : Map[String, Json] = Map([
    (
      "type",
      {
        "const": if encrypted {
          "encrypted_code_execution_result"
        } else {
          "code_execution_result"
        },
      },
    ),
    ("stderr", { "type": "string" }),
    ("return_code", { "type": "number" }),
    (
      "content",
      anthropic_code_execution_file_content_schema("code_execution_output"),
    ),
  ])
  let required : Array[Json] = ["type", "stderr", "return_code"]
  if encrypted {
    properties["encrypted_stdout"] = { "type": "string" }
    required.push("encrypted_stdout")
  } else {
    properties["stdout"] = { "type": "string" }
    required.push("stdout")
  }
  {
    "type": "object",
    "properties": Json::object(properties),
    "required": Json::array(required),
    "additionalProperties": false,
  }
}

///|
fn anthropic_code_execution_extended_output_schemas() -> Array[Json] {
  [
    {
      "type": "object",
      "properties": {
        "type": { "const": "bash_code_execution_result" },
        "content": anthropic_code_execution_file_content_schema(
          "bash_code_execution_output",
        ),
        "stdout": { "type": "string" },
        "stderr": { "type": "string" },
        "return_code": { "type": "number" },
      },
      "required": ["type", "content", "stdout", "stderr", "return_code"],
      "additionalProperties": false,
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "bash_code_execution_tool_result_error" },
        "error_code": { "type": "string" },
      },
      "required": ["type", "error_code"],
      "additionalProperties": false,
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "text_editor_code_execution_tool_result_error" },
        "error_code": { "type": "string" },
      },
      "required": ["type", "error_code"],
      "additionalProperties": false,
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "text_editor_code_execution_view_result" },
        "content": { "type": "string" },
        "file_type": { "type": "string" },
        "num_lines": { "type": ["number", "null"] },
        "start_line": { "type": ["number", "null"] },
        "total_lines": { "type": ["number", "null"] },
      },
      "required": [
        "type", "content", "file_type", "num_lines", "start_line", "total_lines",
      ],
      "additionalProperties": false,
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "text_editor_code_execution_create_result" },
        "is_file_update": { "type": "boolean" },
      },
      "required": ["type", "is_file_update"],
      "additionalProperties": false,
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "text_editor_code_execution_str_replace_result" },
        "lines": {
          "anyOf": [
            { "type": "array", "items": { "type": "string" } },
            { "type": "null" },
          ],
        },
        "new_lines": { "type": ["number", "null"] },
        "new_start": { "type": ["number", "null"] },
        "old_lines": { "type": ["number", "null"] },
        "old_start": { "type": ["number", "null"] },
      },
      "required": [
        "type", "lines", "new_lines", "new_start", "old_lines", "old_start",
      ],
      "additionalProperties": false,
    },
  ]
}

///|
fn anthropic_code_execution_20250522_input_schema() -> Json {
  {
    "type": "object",
    "properties": { "code": { "type": "string" } },
    "required": ["code"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_code_execution_current_input_schema() -> Json {
  {
    "oneOf": [
      {
        "type": "object",
        "properties": {
          "type": { "const": "programmatic-tool-call" },
          "code": { "type": "string" },
        },
        "required": ["type", "code"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "bash_code_execution" },
          "command": { "type": "string" },
        },
        "required": ["type", "command"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "text_editor_code_execution" },
          "command": { "const": "view" },
          "path": { "type": "string" },
        },
        "required": ["type", "command", "path"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "text_editor_code_execution" },
          "command": { "const": "create" },
          "path": { "type": "string" },
          "file_text": { "type": ["string", "null"] },
        },
        "required": ["type", "command", "path"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "text_editor_code_execution" },
          "command": { "const": "str_replace" },
          "path": { "type": "string" },
          "old_str": { "type": "string" },
          "new_str": { "type": "string" },
        },
        "required": ["type", "command", "path", "old_str", "new_str"],
        "additionalProperties": false,
      },
    ],
  }
}

///|
fn anthropic_code_execution_output_schema(include_encrypted : Bool) -> Json {
  let variants : Array[Json] = [anthropic_code_execution_result_schema(false)]
  if include_encrypted {
    variants.push(anthropic_code_execution_result_schema(true))
  }
  variants.append(anthropic_code_execution_extended_output_schemas())
  { "oneOf": Json::array(variants) }
}

///|
fn anthropic_add_code_execution_caller(
  provider_options : Map[String, Json],
  caller_name : String,
) -> Map[String, Json] {
  let result = @provider.copy_provider_metadata(provider_options)
  let anthropic_options : Map[String, Json] = match result.get("anthropic") {
    Some(Object(fields)) => @provider.copy_provider_metadata(fields)
    _ => Map([])
  }
  let allowed_callers : Array[Json] = match
    anthropic_options.get("allowedCallers") {
    Some(Array(values)) => values.copy()
    _ => []
  }
  if !allowed_callers.any(value => value == Json::string(caller_name)) {
    allowed_callers.push(Json::string(caller_name))
  }
  anthropic_options["allowedCallers"] = Json::array(allowed_callers)
  result["anthropic"] = Json::object(anthropic_options)
  result
}

///|
fn anthropic_code_execution_tool(
  id : String,
  input_schema : Json,
  output_schema : Json,
  supports_deferred_results : Bool,
  caller_name : String?,
  on_input_start : @provider_utils.ToolInputStartFunction?,
  on_input_delta : @provider_utils.ToolInputDeltaFunction?,
  on_input_available : @provider_utils.ToolInputAvailableFunction?,
) -> @provider_utils.Tool {
  let tool = @provider_utils.create_provider_executed_tool_factory(
    id~,
    input_schema~,
    output_schema~,
    supports_deferred_results~,
  ).create(on_input_start?, on_input_delta?, on_input_available?)
  match caller_name {
    Some(value) =>
      @provider_utils.experimental_tool_caller(
        tool,
        @provider_utils.ToolCallerDefinition::provider(options => {
          anthropic_add_code_execution_caller(options, value)
        }),
      )
    None => tool
  }
}

///|
/// Create Anthropic's 2025-05-22 provider-executed Python tool.
pub fn code_execution_20250522(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_code_execution_tool(
    "anthropic.code_execution_20250522",
    anthropic_code_execution_20250522_input_schema(),
    anthropic_code_execution_result_schema(false),
    false,
    None,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// Create Anthropic's 2025-08-25 provider-executed code tool.
pub fn code_execution_20250825(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_code_execution_tool(
    "anthropic.code_execution_20250825",
    anthropic_code_execution_current_input_schema(),
    anthropic_code_execution_output_schema(false),
    true,
    Some("code_execution_20250825"),
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// Create Anthropic's current provider-executed code tool.
pub fn code_execution_20260120(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_code_execution_tool(
    "anthropic.code_execution_20260120",
    anthropic_code_execution_current_input_schema(),
    anthropic_code_execution_output_schema(true),
    true,
    Some("code_execution_20260120"),
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn codeExecution_20250522(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  code_execution_20250522(on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// AI SDK-style camel-case spelling.
pub fn codeExecution_20250825(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  code_execution_20250825(on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// AI SDK-style camel-case spelling.
pub fn codeExecution_20260120(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  code_execution_20260120(on_input_start?, on_input_delta?, on_input_available?)
}

///|
fn anthropic_coordinate_schema(length : Int) -> Json {
  {
    "type": "array",
    "items": { "type": "integer" },
    "minItems": length,
    "maxItems": length,
  }
}

///|
fn anthropic_computer_20241022_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": [
          "key", "type", "mouse_move", "left_click", "left_click_drag", "right_click",
          "middle_click", "double_click", "screenshot", "cursor_position",
        ],
      },
      "coordinate": { "type": "array", "items": { "type": "integer" } },
      "text": { "type": "string" },
    },
    "required": ["action"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_computer_20250124_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": [
          "key", "hold_key", "type", "cursor_position", "mouse_move", "left_mouse_down",
          "left_mouse_up", "left_click", "left_click_drag", "right_click", "middle_click",
          "double_click", "triple_click", "scroll", "wait", "screenshot",
        ],
      },
      "coordinate": anthropic_coordinate_schema(2),
      "duration": { "type": "number" },
      "scroll_amount": { "type": "number" },
      "scroll_direction": {
        "type": "string",
        "enum": ["up", "down", "left", "right"],
      },
      "start_coordinate": anthropic_coordinate_schema(2),
      "text": { "type": "string" },
    },
    "required": ["action"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_computer_20251124_input_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": [
          "key", "hold_key", "type", "cursor_position", "mouse_move", "left_mouse_down",
          "left_mouse_up", "left_click", "left_click_drag", "right_click", "middle_click",
          "double_click", "triple_click", "scroll", "wait", "screenshot", "zoom",
        ],
      },
      "coordinate": anthropic_coordinate_schema(2),
      "duration": { "type": "number" },
      "region": anthropic_coordinate_schema(4),
      "scroll_amount": { "type": "number" },
      "scroll_direction": {
        "type": "string",
        "enum": ["up", "down", "left", "right"],
      },
      "start_coordinate": anthropic_coordinate_schema(2),
      "text": { "type": "string" },
    },
    "required": ["action"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_computer_args(
  display_width_px : Int,
  display_height_px : Int,
  display_number : Int?,
  enable_zoom : Bool?,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("displayWidthPx", Json::number(display_width_px.to_double())),
    ("displayHeightPx", Json::number(display_height_px.to_double())),
  ])
  if display_number is Some(value) {
    fields["displayNumber"] = Json::number(value.to_double())
  }
  if enable_zoom is Some(value) {
    fields["enableZoom"] = Json::boolean(value)
  }
  Json::object(fields)
}

///|
fn anthropic_computer_tool(
  id : String,
  input_schema : Json,
  display_width_px : Int,
  display_height_px : Int,
  display_number : Int?,
  enable_zoom : Bool?,
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
    input_schema,
    anthropic_computer_args(
      display_width_px, display_height_px, display_number, enable_zoom,
    ),
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
/// Create Anthropic's 2024-10-22 application-executed computer tool.
pub fn computer_20241022(
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
  anthropic_computer_tool(
    "anthropic.computer_20241022",
    anthropic_computer_20241022_input_schema(),
    display_width_px,
    display_height_px,
    display_number,
    None,
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
/// Create Anthropic's 2025-01-24 application-executed computer tool.
pub fn computer_20250124(
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
  anthropic_computer_tool(
    "anthropic.computer_20250124",
    anthropic_computer_20250124_input_schema(),
    display_width_px,
    display_height_px,
    display_number,
    None,
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
/// Create Anthropic's current application-executed computer tool.
pub fn computer_20251124(
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
  anthropic_computer_tool(
    "anthropic.computer_20251124",
    anthropic_computer_20251124_input_schema(),
    display_width_px,
    display_height_px,
    display_number,
    enable_zoom,
    output_schema,
    execute,
    needs_approval,
    to_model_output,
    on_input_start,
    on_input_delta,
    on_input_available,
  )
}

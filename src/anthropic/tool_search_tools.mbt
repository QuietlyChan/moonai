///|
fn anthropic_tool_search_output_schema() -> Json {
  {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "type": { "const": "tool_reference" },
        "toolName": { "type": "string" },
      },
      "required": ["type", "toolName"],
      "additionalProperties": false,
    },
  }
}

///|
fn anthropic_tool_search_input_schema(field : String) -> Json {
  let properties : Map[String, Json] = Map([
    (field, { "type": "string" }),
    ("limit", { "type": "number" }),
  ])
  {
    "type": "object",
    "properties": Json::object(properties),
    "required": Json::array([Json::string(field)]),
    "additionalProperties": false,
  }
}

///|
fn anthropic_tool_search_tool(
  id : String,
  input_field : String,
  on_input_start : @provider_utils.ToolInputStartFunction?,
  on_input_delta : @provider_utils.ToolInputDeltaFunction?,
  on_input_available : @provider_utils.ToolInputAvailableFunction?,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_executed_tool_factory(
    id~,
    input_schema=anthropic_tool_search_input_schema(input_field),
    output_schema=anthropic_tool_search_output_schema(),
    supports_deferred_results=true,
  ).create(on_input_start?, on_input_delta?, on_input_available?)
}

///|
/// Create Anthropic's regex provider-executed tool search.
pub fn tool_search_regex_20251119(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_tool_search_tool(
    "anthropic.tool_search_regex_20251119", "pattern", on_input_start, on_input_delta,
    on_input_available,
  )
}

///|
/// Create Anthropic's BM25 provider-executed tool search.
pub fn tool_search_bm25_20251119(
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_tool_search_tool(
    "anthropic.tool_search_bm25_20251119", "query", on_input_start, on_input_delta,
    on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn toolSearchRegex_20251119(
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
/// AI SDK-style camel-case spelling.
pub fn toolSearchBm25_20251119(
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

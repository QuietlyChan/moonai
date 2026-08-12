///|
fn mcp_metadata(tool : MCPTool, client_name : String) -> Map[String, Json] {
  let metadata : Map[String, Json] = Map([
    ("clientName", Json::string(client_name)),
    ("toolName", Json::string(tool.name)),
  ])
  let title = match tool.title {
    Some(value) => Some(value)
    None =>
      match tool.annotations {
        Some(Object(fields)) => optional_string(fields, "title")
        _ => None
      }
  }
  if title is Some(value) {
    metadata["title"] = Json::string(value)
  }
  let app_meta = get_mcp_app_tool_meta(tool.meta) catch { _ => None }
  match app_meta {
    Some(app) if app.resource_uri is Some(resource_uri) =>
      metadata["app"] = {
        "resourceUri": resource_uri,
        "mimeType": MCP_APP_MIME_TYPE,
      }
    _ => ()
  }
  metadata
}

///|
async fn mcp_tool_result_to_model_output(
  options : @provider_utils.ToolModelOutputOptions,
) -> @provider_utils.ModelToolResultOutput {
  @async.pause()
  let result = decode_call_tool_result(options.output) catch {
    _ => return @provider_utils.ModelToolResultOutput::json(options.output)
  }
  guard result.content.length() > 0 else {
    return @provider_utils.ModelToolResultOutput::json(result.raw)
  }
  let parts : Array[@provider_utils.ModelToolResultContentPart] = []
  for item in result.content {
    match item {
      { "type": "text", "text": String(text), .. } =>
        parts.push(@provider_utils.ModelToolResultContentPart::text(text))
      {
        "type": "image",
        "data": String(data),
        "mimeType": String(media_type),
        ..
      } =>
        parts.push(
          @provider_utils.ModelToolResultContentPart::file_data(
            data~,
            media_type~,
          ),
        )
      value =>
        parts.push(
          @provider_utils.ModelToolResultContentPart::text(value.stringify()),
        )
    }
  }
  @provider_utils.ModelToolResultOutput::content(parts)
}

///|
/// Convert already-fetched MCP definitions into executable MoonAI tools.
pub fn MCPClient::tools_from_definitions(
  self : MCPClient,
  definitions : ListToolsResult,
  schemas? : Map[String, Json],
) -> @provider_utils.ToolSet {
  let result : @provider_utils.ToolSet = Map([])
  for definition in definitions.tools {
    if schemas is Some(known) && !known.contains(definition.name) {
      continue
    }
    let schema = match schemas {
      Some(known) =>
        known.get(definition.name).unwrap_or(definition.input_schema)
      None => definition.input_schema
    }
    let client = self
    let tool_name = definition.name
    let execute : @provider_utils.ToolExecuteFunction = (input, options) => {
      let call_result = client.call_tool(
        name=tool_name,
        arguments=input,
        options=MCPRequestOptions::new(
          cancellation_token?=options.cancellation_token,
        ),
      )
      if call_result.is_error {
        call_result.raw
      } else {
        call_result.raw
      }
    }
    result[tool_name] = @provider_utils.Tool::dynamic(
      schema,
      description?=definition.description,
      output_schema?=definition.output_schema,
      metadata=mcp_metadata(definition, self.client_info.name),
      execute~,
      to_model_output=mcp_tool_result_to_model_output,
    )
  }
  result
}

///|
/// AI SDK-style spelling for `tools_from_definitions`.
pub fn MCPClient::toolsFromDefinitions(
  self : MCPClient,
  definitions : ListToolsResult,
  schemas? : Map[String, Json],
) -> @provider_utils.ToolSet {
  self.tools_from_definitions(definitions, schemas?)
}

///|
/// Fetch and convert MCP tools into a MoonAI `ToolSet`.
pub async fn MCPClient::tools(
  self : MCPClient,
  schemas? : Map[String, Json],
  options? : MCPRequestOptions,
) -> @provider_utils.ToolSet {
  self.tools_from_definitions(self.list_tools(options?), schemas?)
}

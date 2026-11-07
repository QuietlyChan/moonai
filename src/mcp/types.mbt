///|
/// Client or server implementation information used during initialization.
#derive(Debug, Eq)
pub(all) struct MCPImplementation {
  name : String
  version : String
  title : String?
}

///|
/// Construct MCP implementation metadata.
pub fn MCPImplementation::new(
  name~ : String,
  version~ : String,
  title? : String,
) -> MCPImplementation {
  { name, version, title, }
}

///|
/// MCP capabilities remain open JSON objects for protocol extensions.
pub type MCPClientCapabilities = Json

///|
/// MCP server capabilities remain open JSON objects for protocol extensions.
pub type MCPServerCapabilities = Json

///|
/// The result of the MCP initialize handshake.
#derive(Debug, Eq)
pub(all) struct InitializeResult {
  protocol_version : String
  capabilities : MCPServerCapabilities
  server_info : MCPImplementation
  instructions : String?
  raw : Json
}

///|
/// A tool definition advertised by an MCP server.
#derive(Debug, Eq)
pub(all) struct MCPTool {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  annotations : Json?
  meta : Json?
  raw : Json
}

///|
/// A page of MCP tool definitions.
#derive(Debug, Eq)
pub(all) struct ListToolsResult {
  tools : Array[MCPTool]
  next_cursor : String?
  raw : Json
}

///|
/// One MCP resource descriptor.
#derive(Debug, Eq)
pub(all) struct MCPResource {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  size : Int32?
  raw : Json
}

///|
/// A page of MCP resources.
#derive(Debug, Eq)
pub(all) struct ListResourcesResult {
  resources : Array[MCPResource]
  next_cursor : String?
  raw : Json
}

///|
/// A parameterized MCP resource template.
#derive(Debug, Eq)
pub(all) struct MCPResourceTemplate {
  uri_template : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  raw : Json
}

///|
/// MCP resource templates returned by a server.
#derive(Debug, Eq)
pub(all) struct ListResourceTemplatesResult {
  resource_templates : Array[MCPResourceTemplate]
  next_cursor : String?
  raw : Json
}

///|
/// Text or binary resource content returned by resources/read.
#derive(Debug, Eq)
pub(all) enum MCPResourceContents {
  MCPTextResource(
    uri~ : String,
    name~ : String?,
    title~ : String?,
    mime_type~ : String?,
    text~ : String,
    meta~ : Json?,
    raw~ : Json
  )
  MCPBlobResource(
    uri~ : String,
    name~ : String?,
    title~ : String?,
    mime_type~ : String?,
    blob~ : String,
    meta~ : Json?,
    raw~ : Json
  )
}

///|
/// Resource content returned by resources/read.
#derive(Debug, Eq)
pub(all) struct ReadResourceResult {
  contents : Array[MCPResourceContents]
  raw : Json
}

///|
/// MCP prompt argument metadata.
#derive(Debug, Eq)
pub(all) struct MCPPromptArgument {
  name : String
  description : String?
  required : Bool?
}

///|
/// A prompt advertised by an MCP server.
#derive(Debug, Eq)
pub(all) struct MCPPrompt {
  name : String
  title : String?
  description : String?
  arguments : Array[MCPPromptArgument]
  raw : Json
}

///|
/// A page of MCP prompts.
#derive(Debug, Eq)
pub(all) struct ListPromptsResult {
  prompts : Array[MCPPrompt]
  next_cursor : String?
  raw : Json
}

///|
/// One user or assistant prompt message. Content is retained as protocol JSON.
#derive(Debug, Eq)
pub(all) struct MCPPromptMessage {
  role : String
  content : Json
}

///|
/// A materialized MCP prompt.
#derive(Debug, Eq)
pub(all) struct GetPromptResult {
  description : String?
  messages : Array[MCPPromptMessage]
  raw : Json
}

///|
/// A reference used by completion/complete.
#derive(Debug, Eq)
pub(all) enum MCPCompletionReference {
  MCPPromptReference(name~ : String)
  MCPResourceReference(uri~ : String)
}

///|
/// Parameters for an MCP completion request.
#derive(Debug, Eq)
pub(all) struct CompleteRequestParams {
  reference : MCPCompletionReference
  argument_name : String
  argument_value : String
  context_arguments : Map[String, String]
}

///|
/// Construct an MCP completion request.
pub fn CompleteRequestParams::new(
  reference~ : MCPCompletionReference,
  argument_name~ : String,
  argument_value~ : String,
  context_arguments? : Map[String, String] = Map([]),
) -> CompleteRequestParams {
  { reference, argument_name, argument_value, context_arguments, }
}

///|
/// Values returned by completion/complete.
#derive(Debug, Eq)
pub(all) struct CompleteResult {
  values : Array[String]
  total : Int32?
  has_more : Bool?
  raw : Json
}

///|
/// Result returned by an MCP tool call.
#derive(Debug, Eq)
pub(all) struct CallToolResult {
  content : Array[Json]
  structured_content : Json?
  is_error : Bool
  tool_result : Json?
  raw : Json
}

///|
/// Per-request cancellation and timeout controls.
#derive(Debug)
pub(all) struct MCPRequestOptions {
  cancellation_token : @provider.CancellationToken?
  timeout_ms : Int32?
  max_total_timeout_ms : Int32?
}

///|
/// Construct MCP request controls.
pub fn MCPRequestOptions::new(
  cancellation_token? : @provider.CancellationToken,
  timeout_ms? : Int32,
  max_total_timeout_ms? : Int32,
) -> MCPRequestOptions {
  { cancellation_token, timeout_ms, max_total_timeout_ms, }
}

///|
fn json_object(
  value : Json,
  context : String,
) -> Map[String, Json] raise MCPClientError {
  match value {
    Object(fields) => fields
    _ => raise mcp_error(context + " must be an object")
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  field : String,
  context : String,
) -> String raise MCPClientError {
  match fields.get(field) {
    Some(String(value)) => value
    _ => raise mcp_error(context + " is missing string field " + field)
  }
}

///|
fn optional_string(fields : Map[String, Json], field : String) -> String? {
  match fields.get(field) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn optional_bool(fields : Map[String, Json], field : String) -> Bool? {
  match fields.get(field) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn optional_int(fields : Map[String, Json], field : String) -> Int32? {
  match fields.get(field) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn decode_implementation(
  value : Json,
) -> MCPImplementation raise MCPClientError {
  let fields = json_object(value, "MCP implementation")
  {
    name: required_string(fields, "name", "MCP implementation"),
    version: required_string(fields, "version", "MCP implementation"),
    title: optional_string(fields, "title"),
  }
}

///|
fn decode_initialize_result(
  value : Json,
) -> InitializeResult raise MCPClientError {
  let fields = json_object(value, "initialize result")
  let capabilities = fields.get("capabilities").unwrap_or(Json::empty_object())
  guard capabilities is Object(_) else {
    raise mcp_error("initialize capabilities must be an object")
  }
  guard fields.get("serverInfo") is Some(server_info) else {
    raise mcp_error("initialize result is missing serverInfo")
  }
  {
    protocol_version: required_string(
      fields, "protocolVersion", "initialize result",
    ),
    capabilities,
    server_info: decode_implementation(server_info),
    instructions: optional_string(fields, "instructions"),
    raw: value,
  }
}

///|
fn decode_mcp_tool(value : Json) -> MCPTool raise MCPClientError {
  let fields = json_object(value, "MCP tool")
  let input_schema = fields.get("inputSchema").unwrap_or({ "type": "object" })
  guard input_schema is Object(_) else {
    raise mcp_error("MCP tool inputSchema must be an object")
  }
  {
    name: required_string(fields, "name", "MCP tool"),
    title: optional_string(fields, "title"),
    description: optional_string(fields, "description"),
    input_schema,
    output_schema: fields.get("outputSchema"),
    annotations: fields.get("annotations"),
    meta: fields.get("_meta"),
    raw: value,
  }
}

///|
fn decode_list_tools_result(
  value : Json,
) -> ListToolsResult raise MCPClientError {
  let fields = json_object(value, "tools/list result")
  guard fields.get("tools") is Some(Array(values)) else {
    raise mcp_error("tools/list result is missing tools")
  }
  let tools : Array[MCPTool] = []
  for item in values {
    tools.push(decode_mcp_tool(item))
  }
  { tools, next_cursor: optional_string(fields, "nextCursor"), raw: value, }
}

///|
fn decode_call_tool_result(value : Json) -> CallToolResult raise MCPClientError {
  let fields = json_object(value, "tools/call result")
  let content = match fields.get("content") {
    Some(Array(values)) => values.copy()
    None => []
    _ => raise mcp_error("tools/call content must be an array")
  }
  {
    content,
    structured_content: fields.get("structuredContent"),
    is_error: optional_bool(fields, "isError").unwrap_or(false),
    tool_result: fields.get("toolResult"),
    raw: value,
  }
}

///|
fn decode_resource(value : Json) -> MCPResource raise MCPClientError {
  let fields = json_object(value, "MCP resource")
  {
    uri: required_string(fields, "uri", "MCP resource"),
    name: required_string(fields, "name", "MCP resource"),
    title: optional_string(fields, "title"),
    description: optional_string(fields, "description"),
    mime_type: optional_string(fields, "mimeType"),
    size: optional_int(fields, "size"),
    raw: value,
  }
}

///|
fn decode_list_resources_result(
  value : Json,
) -> ListResourcesResult raise MCPClientError {
  let fields = json_object(value, "resources/list result")
  guard fields.get("resources") is Some(Array(values)) else {
    raise mcp_error("resources/list result is missing resources")
  }
  let resources : Array[MCPResource] = []
  for item in values {
    resources.push(decode_resource(item))
  }
  { resources, next_cursor: optional_string(fields, "nextCursor"), raw: value, }
}

///|
fn decode_resource_template(
  value : Json,
) -> MCPResourceTemplate raise MCPClientError {
  let fields = json_object(value, "MCP resource template")
  {
    uri_template: required_string(
      fields, "uriTemplate", "MCP resource template",
    ),
    name: required_string(fields, "name", "MCP resource template"),
    title: optional_string(fields, "title"),
    description: optional_string(fields, "description"),
    mime_type: optional_string(fields, "mimeType"),
    raw: value,
  }
}

///|
fn decode_list_resource_templates_result(
  value : Json,
) -> ListResourceTemplatesResult raise MCPClientError {
  let fields = json_object(value, "resources/templates/list result")
  guard fields.get("resourceTemplates") is Some(Array(values)) else {
    raise mcp_error(
      "resources/templates/list result is missing resourceTemplates",
    )
  }
  let templates : Array[MCPResourceTemplate] = []
  for item in values {
    templates.push(decode_resource_template(item))
  }
  {
    resource_templates: templates,
    next_cursor: optional_string(fields, "nextCursor"),
    raw: value,
  }
}

///|
fn decode_resource_contents(
  value : Json,
) -> MCPResourceContents raise MCPClientError {
  let fields = json_object(value, "MCP resource contents")
  let uri = required_string(fields, "uri", "MCP resource contents")
  let name = optional_string(fields, "name")
  let title = optional_string(fields, "title")
  let mime_type = optional_string(fields, "mimeType")
  let meta = fields.get("_meta")
  match (fields.get("text"), fields.get("blob")) {
    (Some(String(text)), None) =>
      MCPTextResource(uri~, name~, title~, mime_type~, text~, meta~, raw=value)
    (None, Some(String(blob))) =>
      MCPBlobResource(uri~, name~, title~, mime_type~, blob~, meta~, raw=value)
    _ => raise mcp_error("MCP resource contents require text or blob")
  }
}

///|
fn decode_read_resource_result(
  value : Json,
) -> ReadResourceResult raise MCPClientError {
  let fields = json_object(value, "resources/read result")
  guard fields.get("contents") is Some(Array(values)) else {
    raise mcp_error("resources/read result is missing contents")
  }
  let contents : Array[MCPResourceContents] = []
  for item in values {
    contents.push(decode_resource_contents(item))
  }
  { contents, raw: value, }
}

///|
fn decode_prompt(value : Json) -> MCPPrompt raise MCPClientError {
  let fields = json_object(value, "MCP prompt")
  let arguments : Array[MCPPromptArgument] = []
  match fields.get("arguments") {
    Some(Array(values)) =>
      for item in values {
        let argument = json_object(item, "MCP prompt argument")
        arguments.push({
          name: required_string(argument, "name", "MCP prompt argument"),
          description: optional_string(argument, "description"),
          required: optional_bool(argument, "required"),
        })
      }
    None => ()
    _ => raise mcp_error("MCP prompt arguments must be an array")
  }
  {
    name: required_string(fields, "name", "MCP prompt"),
    title: optional_string(fields, "title"),
    description: optional_string(fields, "description"),
    arguments,
    raw: value,
  }
}

///|
fn decode_list_prompts_result(
  value : Json,
) -> ListPromptsResult raise MCPClientError {
  let fields = json_object(value, "prompts/list result")
  guard fields.get("prompts") is Some(Array(values)) else {
    raise mcp_error("prompts/list result is missing prompts")
  }
  let prompts : Array[MCPPrompt] = []
  for item in values {
    prompts.push(decode_prompt(item))
  }
  { prompts, next_cursor: optional_string(fields, "nextCursor"), raw: value, }
}

///|
fn decode_get_prompt_result(
  value : Json,
) -> GetPromptResult raise MCPClientError {
  let fields = json_object(value, "prompts/get result")
  guard fields.get("messages") is Some(Array(values)) else {
    raise mcp_error("prompts/get result is missing messages")
  }
  let messages : Array[MCPPromptMessage] = []
  for item in values {
    let message = json_object(item, "MCP prompt message")
    guard message.get("content") is Some(content) else {
      raise mcp_error("MCP prompt message is missing content")
    }
    messages.push({
      role: required_string(message, "role", "MCP prompt message"),
      content,
    })
  }
  { description: optional_string(fields, "description"), messages, raw: value, }
}

///|
fn decode_complete_result(value : Json) -> CompleteResult raise MCPClientError {
  let fields = json_object(value, "completion/complete result")
  guard fields.get("completion") is Some(Object(completion)) else {
    raise mcp_error("completion/complete result is missing completion")
  }
  guard completion.get("values") is Some(Array(items)) else {
    raise mcp_error("completion values must be an array")
  }
  let values : Array[String] = []
  for item in items {
    match item {
      String(value) => values.push(value)
      _ => raise mcp_error("completion values must contain strings")
    }
  }
  guard values.length() <= 100 else {
    raise mcp_error("completion result contains more than 100 values")
  }
  {
    values,
    total: optional_int(completion, "total"),
    has_more: optional_bool(completion, "hasMore"),
    raw: value,
  }
}

///|
pub extend MCPImplementation with Debug::{to_repr}

///|
pub extend MCPImplementation with Eq::{not_equal, equal}

///|
pub extend InitializeResult with Debug::{to_repr}

///|
pub extend InitializeResult with Eq::{not_equal, equal}

///|
pub extend MCPTool with Debug::{to_repr}

///|
pub extend MCPTool with Eq::{not_equal, equal}

///|
pub extend ListToolsResult with Debug::{to_repr}

///|
pub extend ListToolsResult with Eq::{not_equal, equal}

///|
pub extend MCPResource with Debug::{to_repr}

///|
pub extend MCPResource with Eq::{not_equal, equal}

///|
pub extend ListResourcesResult with Debug::{to_repr}

///|
pub extend ListResourcesResult with Eq::{not_equal, equal}

///|
pub extend MCPResourceTemplate with Debug::{to_repr}

///|
pub extend MCPResourceTemplate with Eq::{not_equal, equal}

///|
pub extend ListResourceTemplatesResult with Debug::{to_repr}

///|
pub extend ListResourceTemplatesResult with Eq::{not_equal, equal}

///|
pub extend MCPResourceContents with Debug::{to_repr}

///|
pub extend MCPResourceContents with Eq::{not_equal, equal}

///|
pub extend ReadResourceResult with Debug::{to_repr}

///|
pub extend ReadResourceResult with Eq::{not_equal, equal}

///|
pub extend MCPPromptArgument with Debug::{to_repr}

///|
pub extend MCPPromptArgument with Eq::{not_equal, equal}

///|
pub extend MCPPrompt with Debug::{to_repr}

///|
pub extend MCPPrompt with Eq::{not_equal, equal}

///|
pub extend ListPromptsResult with Debug::{to_repr}

///|
pub extend ListPromptsResult with Eq::{not_equal, equal}

///|
pub extend MCPPromptMessage with Debug::{to_repr}

///|
pub extend MCPPromptMessage with Eq::{not_equal, equal}

///|
pub extend GetPromptResult with Debug::{to_repr}

///|
pub extend GetPromptResult with Eq::{not_equal, equal}

///|
pub extend MCPCompletionReference with Debug::{to_repr}

///|
pub extend MCPCompletionReference with Eq::{not_equal, equal}

///|
pub extend CompleteRequestParams with Debug::{to_repr}

///|
pub extend CompleteRequestParams with Eq::{not_equal, equal}

///|
pub extend CompleteResult with Debug::{to_repr}

///|
pub extend CompleteResult with Eq::{not_equal, equal}

///|
pub extend CallToolResult with Debug::{to_repr}

///|
pub extend CallToolResult with Eq::{not_equal, equal}

///|
pub extend MCPRequestOptions with Debug::{to_repr}

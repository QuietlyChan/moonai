///|
/// Handler for server-initiated elicitation requests.
pub type MCPElicitationHandler = async (Json) -> Json

///|
/// Configuration used to create an initialized MCP client.
pub(all) struct MCPClientConfig {
  transport : &MCPTransport
  initialization_options : MCPRequestOptions?
  max_retries : Int
  client_name : String
  client_version : String
  capabilities : MCPClientCapabilities
  initial_initialize_result : InitializeResult?
}

///|
/// Construct MCP client configuration.
pub fn MCPClientConfig::new(
  transport~ : &MCPTransport,
  initialization_options? : MCPRequestOptions,
  max_retries? : Int = 0,
  client_name? : String = "ai-sdk-mcp-client",
  client_version? : String = VERSION,
  capabilities? : MCPClientCapabilities = Json::empty_object(),
  initial_initialize_result? : InitializeResult,
) -> MCPClientConfig raise MCPClientError {
  guard max_retries >= 0 else { raise mcp_error("maxRetries must be >= 0") }
  guard capabilities is Object(_) else {
    raise mcp_error("MCP client capabilities must be an object")
  }
  {
    transport,
    initialization_options,
    max_retries,
    client_name,
    client_version,
    capabilities,
    initial_initialize_result,
  }
}

///|
/// Initialized client for one MCP server.
pub struct MCPClient {
  priv transport : &MCPTransport
  priv client_info : MCPImplementation
  priv client_capabilities : MCPClientCapabilities
  priv max_retries : Int
  priv next_request_id : Ref[Int]
  priv closed : Ref[Bool]
  priv initialize_result_value : Ref[InitializeResult?]
  priv elicitation_handler : Ref[MCPElicitationHandler?]
}

///|
fn effective_timeout(options : MCPRequestOptions?) -> Int? {
  match options {
    None => None
    Some(value) =>
      match (value.timeout_ms, value.max_total_timeout_ms) {
        (Some(left), Some(right)) =>
          Some(if left < right { left } else { right })
        (Some(value), None) | (None, Some(value)) => Some(value)
        (None, None) => None
      }
  }
}

///|
async fn[X] run_mcp_with_options(
  options : MCPRequestOptions?,
  operation : async () -> X,
) -> X {
  let cancellation_token = match options {
    Some(value) => value.cancellation_token
    None => None
  }
  @provider.check_cancellation(cancellation_token)
  match effective_timeout(options) {
    Some(timeout) if timeout >= 0 =>
      @async.with_timeout(
        timeout,
        operation,
        error=mcp_error("MCP request timed out after \{timeout}ms"),
      )
    _ => operation()
  }
}

///|
fn response_for_id(
  messages : Array[JSONRPCMessage],
  id : JSONRPCId,
) -> Json raise MCPClientError {
  for message in messages {
    match message {
      JSONRPCResponse(id=response_id, result~) if response_id == id =>
        return result
      JSONRPCError(id=response_id, error~) if response_id == id =>
        raise MCPClientError::new(
          message=error.message,
          code=error.code,
          data?=error.data,
        )
      _ => ()
    }
  }
  raise mcp_error("MCP transport did not return a response for request id")
}

///|
async fn MCPClient::handle_server_request(
  self : MCPClient,
  message : JSONRPCMessage,
) -> Unit {
  match message {
    JSONRPCRequest(id~, method_name="ping", ..) =>
      ignore(
        self.transport.send(
          JSONRPCMessage::response(id~),
          MCPTransportSendOptions::new(),
        ),
      )
    JSONRPCRequest(id~, method_name="elicitation/create", params~) => {
      let response = match self.elicitation_handler.val {
        Some(handler) =>
          JSONRPCMessage::response(
            id~,
            result=handler(params.unwrap_or(Json::empty_object())),
          ) catch {
            error =>
              JSONRPCMessage::error(
                id~,
                code=-32603,
                message="Failed to handle elicitation request: " +
                  @debug.to_string(error),
              )
          }
        None =>
          JSONRPCMessage::error(
            id~,
            code=-32601,
            message="No elicitation handler registered on client",
          )
      }
      ignore(self.transport.send(response, MCPTransportSendOptions::new()))
    }
    JSONRPCRequest(id~, method_name~, ..) =>
      ignore(
        self.transport.send(
          JSONRPCMessage::error(
            id~,
            code=-32601,
            message="Unsupported request method: " + method_name,
          ),
          MCPTransportSendOptions::new(),
        ),
      )
    _ => ()
  }
}

///|
async fn MCPClient::request_json(
  self : MCPClient,
  method_name : String,
  params : Json?,
  options : MCPRequestOptions?,
) -> Json {
  guard !self.closed.val else { raise mcp_error("MCP client is closed") }
  let id = JSONRPCNumberId(self.next_request_id.val)
  self.next_request_id.val = self.next_request_id.val + 1
  let cancellation_token = match options {
    Some(value) => value.cancellation_token
    None => None
  }
  let messages = run_mcp_with_options(options, () => {
    self.transport.send(
      JSONRPCMessage::request(id~, method_name~, params?),
      MCPTransportSendOptions::new(cancellation_token?),
    )
  })
  for message in messages {
    if message is JSONRPCRequest(..) {
      self.handle_server_request(message)
    }
  }
  response_for_id(messages, id)
}

///|
async fn MCPClient::notification(
  self : MCPClient,
  method_name : String,
  params? : Json,
  options? : MCPRequestOptions,
) -> Unit {
  let cancellation_token = match options {
    Some(value) => value.cancellation_token
    None => None
  }
  ignore(
    run_mcp_with_options(options, () => {
      self.transport.send(
        JSONRPCMessage::notification(method_name~, params?),
        MCPTransportSendOptions::new(cancellation_token?),
      )
    }),
  )
}

///|
fn protocol_is_supported(version : String) -> Bool {
  supported_protocol_versions.contains(version)
}

///|
/// Start a transport and perform the MCP initialize handshake.
pub async fn create_mcp_client(config : MCPClientConfig) -> MCPClient {
  let client = MCPClient::{
    transport: config.transport,
    client_info: MCPImplementation::new(
      name=config.client_name,
      version=config.client_version,
    ),
    client_capabilities: config.capabilities,
    max_retries: config.max_retries,
    next_request_id: Ref(0),
    closed: Ref(false),
    initialize_result_value: Ref(None),
    elicitation_handler: Ref(None),
  }
  run_mcp_with_options(config.initialization_options, () => {
    config.transport.start()
  }) catch {
    error => {
      config.transport.close(MCPTransportCloseOptions::new()) catch {
        _ => ()
      }
      raise error
    }
  }
  let initialized = try {
    let result = match config.initial_initialize_result {
      Some(value) => value
      None => {
        let raw = client.request_json(
          "initialize",
          Some({
            "protocolVersion": LATEST_PROTOCOL_VERSION,
            "capabilities": config.capabilities,
            "clientInfo": {
              "name": config.client_name,
              "version": config.client_version,
            },
          }),
          config.initialization_options,
        )
        decode_initialize_result(raw)
      }
    }
    guard protocol_is_supported(result.protocol_version) else {
      raise mcp_error(
        "Unsupported MCP protocol version: " + result.protocol_version,
      )
    }
    config.transport.set_protocol_version(result.protocol_version)
    client.initialize_result_value.val = Some(result)
    if config.initial_initialize_result is None {
      client.notification("notifications/initialized")
    }
    true
  } catch {
    error => {
      config.transport.close(MCPTransportCloseOptions::new()) catch {
        _ => ()
      }
      raise error
    }
  }
  ignore(initialized)
  client
}

///|
/// AI SDK-style spelling for `create_mcp_client`.
pub async fn createMCPClient(config : MCPClientConfig) -> MCPClient {
  create_mcp_client(config)
}

///|
/// Compatibility spelling retained for AI SDK's former experimental export.
pub async fn experimental_create_mcp_client(
  config : MCPClientConfig,
) -> MCPClient {
  create_mcp_client(config)
}

///|
/// Full initialize result for this client.
pub fn MCPClient::initialize_result(
  self : MCPClient,
) -> InitializeResult raise MCPClientError {
  self.initialize_result_value.val.unwrap_or_else(() => {
    raise mcp_error("MCP client is not initialized")
  })
}

///|
/// Information reported by the connected MCP server.
pub fn MCPClient::server_info(
  self : MCPClient,
) -> MCPImplementation raise MCPClientError {
  self.initialize_result().server_info
}

///|
/// Optional server usage instructions.
pub fn MCPClient::instructions(
  self : MCPClient,
) -> String? raise MCPClientError {
  self.initialize_result().instructions
}

///|
/// Client capabilities advertised during initialization.
pub fn MCPClient::capabilities(self : MCPClient) -> MCPClientCapabilities {
  self.client_capabilities
}

///|
fn pagination_params(cursor : String?) -> Json? {
  match cursor {
    Some(value) => Some({ "cursor": value })
    None => None
  }
}

///|
/// List tools exposed by the MCP server.
pub async fn MCPClient::list_tools(
  self : MCPClient,
  cursor? : String,
  options? : MCPRequestOptions,
) -> ListToolsResult {
  decode_list_tools_result(
    self.request_json("tools/list", pagination_params(cursor), options),
  )
}

///|
/// AI SDK-style spelling for `list_tools`.
pub async fn MCPClient::listTools(
  self : MCPClient,
  cursor? : String,
  options? : MCPRequestOptions,
) -> ListToolsResult {
  self.list_tools(cursor?, options?)
}

///|
fn retryable_mcp_error(error : Error) -> Bool {
  match error {
    MCPClientError(code=Some(_), ..) => false
    MCPClientError(status_code=Some(status), ..) =>
      status == 408 || status == 409 || status == 429 || status >= 500
    _ => false
  }
}

///|
/// Invoke one MCP tool, retrying only transient transport failures.
pub async fn MCPClient::call_tool(
  self : MCPClient,
  name~ : String,
  arguments? : Json = Json::empty_object(),
  options? : MCPRequestOptions,
) -> CallToolResult {
  guard arguments is Object(_) else {
    raise mcp_error("MCP tool arguments must be an object")
  }
  let mut attempt = 0
  for ;; {
    let result = decode_call_tool_result(
      self.request_json(
        "tools/call",
        Some({ "name": name, "arguments": arguments }),
        options,
      ),
    ) catch {
      error if attempt < self.max_retries && retryable_mcp_error(error) => {
        let delay = 100 * (1 << attempt)
        attempt = attempt + 1
        @async.sleep(delay)
        continue
      }
      error => raise error
    }
    return result
  }
}

///|
/// AI SDK-style spelling for `call_tool`.
pub async fn MCPClient::callTool(
  self : MCPClient,
  name~ : String,
  arguments? : Json = Json::empty_object(),
  options? : MCPRequestOptions,
) -> CallToolResult {
  self.call_tool(name~, arguments~, options?)
}

///|
/// List resources exposed by the MCP server.
pub async fn MCPClient::list_resources(
  self : MCPClient,
  cursor? : String,
  options? : MCPRequestOptions,
) -> ListResourcesResult {
  decode_list_resources_result(
    self.request_json("resources/list", pagination_params(cursor), options),
  )
}

///|
/// AI SDK-style spelling for `list_resources`.
pub async fn MCPClient::listResources(
  self : MCPClient,
  cursor? : String,
  options? : MCPRequestOptions,
) -> ListResourcesResult {
  self.list_resources(cursor?, options?)
}

///|
/// Read one MCP resource.
pub async fn MCPClient::read_resource(
  self : MCPClient,
  uri~ : String,
  options? : MCPRequestOptions,
) -> ReadResourceResult {
  decode_read_resource_result(
    self.request_json("resources/read", Some({ "uri": uri }), options),
  )
}

///|
/// AI SDK-style spelling for `read_resource`.
pub async fn MCPClient::readResource(
  self : MCPClient,
  uri~ : String,
  options? : MCPRequestOptions,
) -> ReadResourceResult {
  self.read_resource(uri~, options?)
}

///|
/// List parameterized resource templates.
pub async fn MCPClient::list_resource_templates(
  self : MCPClient,
  cursor? : String,
  options? : MCPRequestOptions,
) -> ListResourceTemplatesResult {
  decode_list_resource_templates_result(
    self.request_json(
      "resources/templates/list",
      pagination_params(cursor),
      options,
    ),
  )
}

///|
/// AI SDK-style spelling for `list_resource_templates`.
pub async fn MCPClient::listResourceTemplates(
  self : MCPClient,
  cursor? : String,
  options? : MCPRequestOptions,
) -> ListResourceTemplatesResult {
  self.list_resource_templates(cursor?, options?)
}

///|
/// List prompts exposed by the MCP server.
pub async fn MCPClient::experimental_list_prompts(
  self : MCPClient,
  cursor? : String,
  options? : MCPRequestOptions,
) -> ListPromptsResult {
  decode_list_prompts_result(
    self.request_json("prompts/list", pagination_params(cursor), options),
  )
}

///|
/// Materialize one MCP prompt.
pub async fn MCPClient::experimental_get_prompt(
  self : MCPClient,
  name~ : String,
  arguments? : Json = Json::empty_object(),
  options? : MCPRequestOptions,
) -> GetPromptResult {
  guard arguments is Object(_) else {
    raise mcp_error("MCP prompt arguments must be an object")
  }
  decode_get_prompt_result(
    self.request_json(
      "prompts/get",
      Some({ "name": name, "arguments": arguments }),
      options,
    ),
  )
}

///|
fn completion_reference_to_json(reference : MCPCompletionReference) -> Json {
  match reference {
    MCPPromptReference(name~) => ({ "type": "ref/prompt", "name": name } : Json)
    MCPResourceReference(uri~) =>
      ({ "type": "ref/resource", "uri": uri } : Json)
  }
}

///|
/// Request server-side argument completion.
pub async fn MCPClient::complete(
  self : MCPClient,
  params : CompleteRequestParams,
  options? : MCPRequestOptions,
) -> CompleteResult {
  let fields : Map[String, Json] = Map([
    ("ref", completion_reference_to_json(params.reference)),
    (
      "argument",
      ({ "name": params.argument_name, "value": params.argument_value } : Json),
    ),
  ])
  if params.context_arguments.length() > 0 {
    let arguments : Map[String, Json] = Map([])
    for entry in params.context_arguments.iter2() {
      arguments[entry.0] = Json::string(entry.1)
    }
    fields["context"] = { "arguments": Json::object(arguments) }
  }
  decode_complete_result(
    self.request_json(
      "completion/complete",
      Some(Json::object(fields)),
      options,
    ),
  )
}

///|
/// Register the handler used for server-initiated elicitation/create requests.
pub fn MCPClient::on_elicitation_request(
  self : MCPClient,
  handler : MCPElicitationHandler,
) -> Unit {
  self.elicitation_handler.val = Some(handler)
}

///|
/// AI SDK-style spelling for `on_elicitation_request`.
pub fn MCPClient::onElicitationRequest(
  self : MCPClient,
  handler : MCPElicitationHandler,
) -> Unit {
  self.on_elicitation_request(handler)
}

///|
/// Close the MCP client and its transport.
pub async fn MCPClient::close(
  self : MCPClient,
  options? : MCPTransportCloseOptions = MCPTransportCloseOptions::new(),
) -> Unit {
  guard !self.closed.val else { return }
  self.closed.val = true
  self.transport.close(options)
}

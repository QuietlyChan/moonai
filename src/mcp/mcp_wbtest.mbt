///|
test "JSON-RPC validation distinguishes requests, notifications, and errors" {
  assert_eq(
    validate_json_rpc_message({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/list",
      "params": Json::empty_object(),
    }),
    JSONRPCRequest(
      id=JSONRPCNumberId(1),
      method_name="tools/list",
      params=Some(Json::empty_object()),
    ),
  )
  assert_true(
    validate_json_rpc_message({
      "jsonrpc": "2.0",
      "method": "notifications/initialized",
    })
    is JSONRPCNotification(method_name="notifications/initialized", ..),
  )
  assert_true(
    validate_json_rpc_message({
      "jsonrpc": "2.0",
      "id": "call-1",
      "error": { "code": -32602, "message": "bad params" },
    })
    is JSONRPCError(id=JSONRPCStringId("call-1"), error={ code: -32602, .. }),
  )
}

///|
async test "MCP client initializes, lists tools, and executes converted tools" {
  let transport = MockMCPTransport::new(responses=[
    [
      JSONRPCMessage::response(id=JSONRPCNumberId(0), result={
        "protocolVersion": LATEST_PROTOCOL_VERSION,
        "capabilities": { "tools": Json::empty_object() },
        "serverInfo": { "name": "fixture", "version": "1.0.0" },
        "instructions": "Use fixture tools",
      }),
    ],
    [],
    [
      JSONRPCMessage::response(id=JSONRPCNumberId(1), result={
        "tools": [
          {
            "name": "weather",
            "title": "Weather",
            "description": "Read weather",
            "inputSchema": {
              "type": "object",
              "properties": { "city": { "type": "string" } },
            },
          },
        ],
      }),
    ],
    [
      JSONRPCMessage::response(id=JSONRPCNumberId(2), result={
        "content": [{ "type": "text", "text": "sunny" }],
        "isError": false,
      }),
    ],
  ])
  let client = create_mcp_client(
    MCPClientConfig::new(transport=transport as &MCPTransport),
  )
  assert_eq(client.server_info().name, "fixture")
  assert_eq(client.instructions(), Some("Use fixture tools"))
  let tools = client.tools()
  assert_true(tools.contains("weather"))
  let output = tools["weather"].execute(
    { "city": "Shanghai" },
    @provider_utils.ToolExecutionOptions::new(tool_call_id="call-1"),
  )
  assert_true(output is Some({ "content": [_, ..], "isError": false, .. }))
  assert_eq(transport.sent_messages.length(), 4)
  assert_true(
    transport.sent_messages[1]
    is JSONRPCNotification(method_name="notifications/initialized", ..),
  )
  client.close()
  assert_true(transport.is_closed())
}

///|
priv struct MCPHttpFixtureTransport {
  requests : Array[@provider_utils.HttpRequest]
  responses : Array[@provider_utils.HttpResponse]
  next : Ref[Int]
}

///|
fn MCPHttpFixtureTransport::new(
  responses : Array[@provider_utils.HttpResponse],
) -> MCPHttpFixtureTransport {
  { requests: [], responses, next: Ref(0) }
}

///|
impl @provider_utils.HttpTransport for MCPHttpFixtureTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  guard self.next.val < self.responses.length() else {
    return @provider_utils.HttpResponse::text(status_code=202, body="")
  }
  let response = self.responses[self.next.val]
  self.next.val = self.next.val + 1
  response
}

///|
impl @provider_utils.HttpTransport for MCPHttpFixtureTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming response is not used by MCP buffered transport tests")
}

///|
async test "HTTP MCP transport retains session and terminates it with DELETE" {
  let fixture = MCPHttpFixtureTransport::new([
    @provider_utils.HttpResponse::text(
      status_code=200,
      body=JSONRPCMessage::response(id=JSONRPCNumberId(7), result={ "ok": true })
        .to_json()
        .stringify(),
      headers={
        "content-type": "application/json",
        "mcp-session-id": "session-1",
      },
    ),
    @provider_utils.HttpResponse::text(status_code=204, body=""),
  ])
  let transport = HttpMCPTransport::new(
    url="https://mcp.example.test/api",
    http_transport=fixture,
  )
  transport.start()
  let messages = transport.send(
    JSONRPCMessage::request(id=JSONRPCNumberId(7), method_name="tools/list"),
    MCPTransportSendOptions::new(),
  )
  assert_eq(messages.length(), 1)
  assert_eq(transport.session_id(), Some("session-1"))
  transport.close(MCPTransportCloseOptions::new())
  assert_eq(fixture.requests.length(), 2)
  assert_eq(fixture.requests[1].meth, @provider_utils.HttpDelete)
  assert_eq(
    fixture.requests[1].headers.get("mcp-session-id"),
    Some("session-1"),
  )
}

///|
test "MCP Apps metadata splits visibility and fingerprints deterministically" {
  let app_tool = decode_mcp_tool({
    "name": "render",
    "inputSchema": { "type": "object" },
    "_meta": {
      "ui": { "resourceUri": "ui://weather/app", "visibility": ["app"] },
    },
  })
  let plain_tool = decode_mcp_tool({
    "name": "search",
    "inputSchema": { "type": "object" },
  })
  let definitions : ListToolsResult = {
    tools: [app_tool, plain_tool],
    next_cursor: None,
    raw: Json::empty_object(),
  }
  let split = split_mcp_app_tools(definitions)
  assert_eq(split.model_visible.tools.length(), 1)
  assert_eq(split.app_visible.tools.length(), 1)
  let resource : MCPAppResource = {
    uri: "ui://weather/app",
    mime_type: MCP_APP_MIME_TYPE,
    html: "<main>weather</main>",
    meta: None,
  }
  let first = fingerprint_mcp_app_resource(resource)
  let second = fingerprint_mcp_app_resource(resource)
  assert_eq(first, second)
  assert_false(detect_mcp_app_resource_drift(first, second))
}

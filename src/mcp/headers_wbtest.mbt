///|
test "MCP header values pass plain ASCII through" {
  assert_eq(encode_mcp_header_value("weather"), "weather")
  assert_eq(encode_mcp_header_value("files/report.pdf"), "files/report.pdf")
}

///|
test "MCP header values encode padding, non-ASCII, and sentinels" {
  // Leading/trailing whitespace cannot survive as-is.
  let padded = encode_mcp_header_value(" padded ")
  assert_true(padded.has_prefix("=?base64?") && padded.has_suffix("?="))
  // Non-ASCII names are encoded.
  let unicode = encode_mcp_header_value("天气")
  assert_true(unicode.has_prefix("=?base64?") && unicode.has_suffix("?="))
  // A value that already looks like a sentinel is re-encoded verbatim.
  let fake = "=?base64?bm90LWE?="
  let reencoded = encode_mcp_header_value(fake)
  assert_true(reencoded != fake)
  assert_true(reencoded.has_prefix("=?base64?") && reencoded.has_suffix("?="))
}

///|
test "MCP standard request headers tag method and name" {
  let request = JSONRPCMessage::request(
    id=JSONRPCNumberId(3),
    method_name="tools/call",
    params={ "name": "weather", "arguments": { "city": "Shanghai" } },
  )
  let headers = mcp_standard_request_headers(request)
  assert_eq(headers.get("Mcp-Method"), Some("tools/call"))
  assert_eq(headers.get("Mcp-Name"), Some("weather"))
}

///|
test "MCP standard request headers name resources by URI" {
  let request = JSONRPCMessage::request(
    id=JSONRPCNumberId(4),
    method_name="resources/read",
    params={ "uri": "file:///logs/app.txt" },
  )
  let headers = mcp_standard_request_headers(request)
  assert_eq(headers.get("Mcp-Method"), Some("resources/read"))
  assert_eq(headers.get("Mcp-Name"), Some("file:///logs/app.txt"))
}

///|
test "MCP standard request headers skip unnamed methods and notifications" {
  let listed = mcp_standard_request_headers(
    JSONRPCMessage::request(id=JSONRPCNumberId(5), method_name="tools/list"),
  )
  assert_eq(listed.get("Mcp-Method"), Some("tools/list"))
  assert_true(listed.get("Mcp-Name") is None)
  let notification = mcp_standard_request_headers(
    JSONRPCMessage::notification(method_name="notifications/initialized"),
  )
  assert_true(notification.get("Mcp-Method") is None)
  assert_true(notification.get("Mcp-Name") is None)
}

///|
async test "HTTP MCP transport sends Mcp-Method and Mcp-Name headers" {
  let fixture = MCPHttpFixtureTransport::new([
    @provider_utils.HttpResponse::text(
      status_code=200,
      body=JSONRPCMessage::response(id=JSONRPCNumberId(9), result={
          "content": [{ "type": "text", "text": "ok" }],
          "isError": false,
        })
        .to_json()
        .stringify(),
      headers={ "content-type": "application/json" },
    ),
  ])
  let transport = HttpMCPTransport::new(
    url="https://mcp.example.test/api",
    http_transport=fixture,
  )
  transport.start()
  transport.send(
    JSONRPCMessage::request(id=JSONRPCNumberId(9), method_name="tools/call", params={
      "name": "weather",
      "arguments": {},
    }),
    MCPTransportSendOptions::new(),
  )
  |> ignore
  let headers = fixture.requests[0].headers
  assert_eq(headers.get("Mcp-Method"), Some("tools/call"))
  assert_eq(headers.get("Mcp-Name"), Some("weather"))
}

///|
async test "MCP tools() follows next_cursor across pages (#19246)" {
  let transport = MockMCPTransport::new(responses=[
    [
      JSONRPCMessage::response(id=JSONRPCNumberId(0), result={
        "protocolVersion": LATEST_PROTOCOL_VERSION,
        "capabilities": { "tools": Json::empty_object() },
        "serverInfo": { "name": "fixture", "version": "1.0.0" },
      }),
    ],
    [],
    [
      JSONRPCMessage::response(id=JSONRPCNumberId(1), result={
        "tools": [
          {
            "name": "weather",
            "description": "Read weather",
            "inputSchema": { "type": "object", "properties": {} },
          },
        ],
        "nextCursor": "page-2",
      }),
    ],
    [
      JSONRPCMessage::response(id=JSONRPCNumberId(2), result={
        "tools": [
          {
            "name": "clock",
            "description": "Read clock",
            "inputSchema": { "type": "object", "properties": {} },
          },
        ],
      }),
    ],
  ])
  let client = create_mcp_client(
    MCPClientConfig::new(transport=transport as &MCPTransport),
  )
  let tools = client.tools()
  assert_true(tools.contains("weather"))
  assert_true(tools.contains("clock"))
  // initialize + initialized + page 1 + page 2
  assert_eq(transport.sent_messages.length(), 4)
  assert_true(
    transport.sent_messages[3]
    is JSONRPCRequest(method_name="tools/list", params=Some(_), ..),
  )
  match transport.sent_messages[3] {
    JSONRPCRequest(params=Some(Object(fields)), ..) =>
      assert_eq(fields.get("cursor"), Some(Json::string("page-2")))
    _ => fail("expected a tools/list request with a cursor")
  }
  client.close()
}

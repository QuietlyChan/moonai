///|
/// Request-scoped options passed to an MCP transport.
pub(all) struct MCPTransportSendOptions {
  cancellation_token : @provider.CancellationToken?
  related_request_id : JSONRPCId?
  resumption_token : String?
} derive(Debug)

///|
/// Construct MCP transport send options.
pub fn MCPTransportSendOptions::new(
  cancellation_token? : @provider.CancellationToken,
  related_request_id? : JSONRPCId,
  resumption_token? : String,
) -> MCPTransportSendOptions {
  { cancellation_token, related_request_id, resumption_token }
}

///|
/// Cleanup options passed to an MCP transport.
pub(all) struct MCPTransportCloseOptions {
  cancellation_token : @provider.CancellationToken?
} derive(Debug)

///|
/// Construct MCP transport close options.
pub fn MCPTransportCloseOptions::new(
  cancellation_token? : @provider.CancellationToken,
) -> MCPTransportCloseOptions {
  { cancellation_token, }
}

///|
/// Runtime-neutral MCP transport.
///
/// `send` returns all messages observed while processing the outgoing frame.
/// This request-oriented form maps naturally to MoonBit structured concurrency
/// while preserving the MCP message model used by HTTP, SSE, stdio, and tests.
pub(open) trait MCPTransport {
  async fn start(Self) -> Unit
  async fn send(Self, JSONRPCMessage, MCPTransportSendOptions) -> Array[
    JSONRPCMessage,
  ]
  async fn close(Self, MCPTransportCloseOptions) -> Unit
  fn protocol_version(Self) -> String?
  fn set_protocol_version(Self, String) -> Unit
}

///|
/// A deterministic transport for MCP client tests and local integrations.
pub struct MockMCPTransport {
  responses : Array[Array[JSONRPCMessage]]
  sent_messages : Array[JSONRPCMessage]
  priv next_response : Ref[Int]
  priv started : Ref[Bool]
  priv closed : Ref[Bool]
  priv negotiated_version : Ref[String?]
}

///|
/// Construct a mock transport with one response batch per send.
pub fn MockMCPTransport::new(
  responses? : Array[Array[JSONRPCMessage]] = [],
) -> MockMCPTransport {
  {
    responses,
    sent_messages: [],
    next_response: Ref(0),
    started: Ref(false),
    closed: Ref(false),
    negotiated_version: Ref(None),
  }
}

///|
/// Whether the mock transport was started.
pub fn MockMCPTransport::is_started(self : MockMCPTransport) -> Bool {
  self.started.val
}

///|
/// Whether the mock transport was closed.
pub fn MockMCPTransport::is_closed(self : MockMCPTransport) -> Bool {
  self.closed.val
}

///|
pub impl MCPTransport for MockMCPTransport with fn start(self) {
  guard !self.started.val else {
    raise mcp_error("MockMCPTransport already started")
  }
  self.started.val = true
}

///|
pub impl MCPTransport for MockMCPTransport with fn send(self, message, options) {
  @provider.check_cancellation(options.cancellation_token)
  guard self.started.val && !self.closed.val else {
    raise mcp_error("MockMCPTransport is not connected")
  }
  self.sent_messages.push(message)
  guard self.next_response.val < self.responses.length() else { return [] }
  let response = self.responses[self.next_response.val].copy()
  self.next_response.val = self.next_response.val + 1
  response
}

///|
pub impl MCPTransport for MockMCPTransport with fn close(self, options) {
  @provider.check_cancellation(options.cancellation_token)
  self.closed.val = true
}

///|
pub impl MCPTransport for MockMCPTransport with fn protocol_version(self) {
  self.negotiated_version.val
}

///|
pub impl MCPTransport for MockMCPTransport with fn set_protocol_version(
  self,
  version,
) {
  self.negotiated_version.val = Some(version)
}

///|
fn header_value(headers : Map[String, String], name : String) -> String? {
  match headers.get(name) {
    Some(value) => Some(value)
    None => {
      let target = name.to_lower()
      for entry in headers.iter2() {
        if entry.0.to_lower() == target {
          return Some(entry.1)
        }
      }
      None
    }
  }
}

///|
fn mcp_common_headers(
  configured : Map[String, String],
  protocol_version : String?,
  session_id : String?,
) -> Map[String, String] {
  let headers = @provider_utils.copy_headers(configured)
  headers["mcp-protocol-version"] = protocol_version.unwrap_or(
    LATEST_PROTOCOL_VERSION,
  )
  if session_id is Some(value) {
    headers["mcp-session-id"] = value
  }
  @provider_utils.with_user_agent_suffix(headers, ["moonai/mcp/" + VERSION])
}

///|
fn decode_sse_messages(
  text : String,
) -> Array[JSONRPCMessage] raise MCPClientError {
  let messages : Array[JSONRPCMessage] = []
  let buffer = @provider_utils.EventSourceBuffer::new()
  for raw_line in text.split("\n") {
    if buffer.feed_line(raw_line.to_owned()) is Some(payload) {
      if payload != "" {
        messages.push(parse_json_rpc_message(payload))
      }
    }
  }
  if buffer.flush() is Some(payload) && payload != "" {
    messages.push(parse_json_rpc_message(payload))
  }
  messages
}

///|
fn decode_http_mcp_messages(
  body : String,
  content_type : String,
) -> Array[JSONRPCMessage] raise MCPClientError {
  if content_type.to_lower().contains("text/event-stream") {
    return decode_sse_messages(body)
  }
  let value = @json.parse(body) catch {
    error =>
      raise MCPClientError::new(
        message="MCP HTTP transport failed to parse response",
        response_body=body,
        cause=@debug.to_string(error),
      )
  }
  match value {
    Array(values) => {
      let messages : Array[JSONRPCMessage] = []
      for item in values {
        messages.push(validate_json_rpc_message(item))
      }
      messages
    }
    _ => [validate_json_rpc_message(value)]
  }
}

///|
/// Streamable HTTP MCP transport.
pub struct HttpMCPTransport {
  url : String
  configured_headers : Map[String, String]
  terminate_session_on_close : Bool
  http_transport : &@provider_utils.HttpTransport
  priv started : Ref[Bool]
  priv session_id_value : Ref[String?]
  priv protocol_version_value : Ref[String?]
  priv on_session_id_change : ((String?) -> Unit)?
  priv on_session_expired : ((String) -> Unit)?
}

///|
/// Construct a Streamable HTTP MCP transport.
pub fn HttpMCPTransport::new(
  url~ : String,
  headers? : Map[String, String] = Map([]),
  initial_session_id? : String,
  initial_protocol_version? : String,
  on_session_id_change? : (String?) -> Unit,
  on_session_expired? : (String) -> Unit,
  terminate_session_on_close? : Bool = true,
  http_transport? : &@provider_utils.HttpTransport,
) -> HttpMCPTransport {
  {
    url,
    configured_headers: @provider_utils.copy_headers(headers),
    terminate_session_on_close,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
    started: Ref(false),
    session_id_value: Ref(initial_session_id),
    protocol_version_value: Ref(initial_protocol_version),
    on_session_id_change,
    on_session_expired,
  }
}

///|
/// Current Streamable HTTP session identifier.
pub fn HttpMCPTransport::session_id(self : HttpMCPTransport) -> String? {
  self.session_id_value.val
}

///|
fn HttpMCPTransport::set_session_id(
  self : HttpMCPTransport,
  value : String?,
) -> Unit {
  guard self.session_id_value.val != value else { return }
  self.session_id_value.val = value
  if self.on_session_id_change is Some(callback) {
    callback(value)
  }
}

///|
pub impl MCPTransport for HttpMCPTransport with fn start(self) {
  guard !self.started.val else {
    raise mcp_error("MCP HTTP transport already started")
  }
  self.started.val = true
}

///|
pub impl MCPTransport for HttpMCPTransport with fn send(self, message, options) {
  @provider.check_cancellation(options.cancellation_token)
  guard self.started.val else {
    raise mcp_error("MCP HTTP transport is not connected")
  }
  let is_initialize = message is JSONRPCRequest(method_name="initialize", ..)
  let request_session = if is_initialize {
    None
  } else {
    self.session_id_value.val
  }
  let headers = mcp_common_headers(
    self.configured_headers,
    self.protocol_version_value.val,
    request_session,
  )
  headers["Content-Type"] = "application/json"
  headers["Accept"] = "application/json, text/event-stream"
  let body = message.to_json().stringify()
  let response = self.http_transport.fetch(
    @provider_utils.HttpRequest::post(
      url=self.url,
      headers~,
      body=@utf8.encode(body),
    ),
  ) catch {
    error =>
      raise MCPClientError::new(
        message="MCP HTTP transport request failed",
        url=self.url,
        cause=@debug.to_string(error),
      )
  }
  if header_value(response.headers, "mcp-session-id") is Some(session_id) {
    self.set_session_id(Some(session_id))
  }
  let response_body = response.body_text() catch {
    error =>
      raise MCPClientError::new(
        message="MCP HTTP transport response was not UTF-8",
        status_code=response.status_code,
        url=self.url,
        cause=@debug.to_string(error),
      )
  }
  guard response.is_success() else {
    if response.status_code == 404 && request_session is Some(expired) {
      self.set_session_id(None)
      if self.on_session_expired is Some(callback) {
        callback(expired)
      }
    }
    raise MCPClientError::new(
      message="MCP HTTP transport returned HTTP \{response.status_code} \{response.reason}",
      status_code=response.status_code,
      url=self.url,
      response_body~,
    )
  }
  if response.status_code == 202 || response_body.trim() == "" {
    return []
  }
  decode_http_mcp_messages(
    response_body,
    header_value(response.headers, "content-type").unwrap_or("application/json"),
  )
}

///|
pub impl MCPTransport for HttpMCPTransport with fn close(self, options) {
  @provider.check_cancellation(options.cancellation_token)
  if self.started.val &&
    self.terminate_session_on_close &&
    self.session_id_value.val is Some(session_id) {
    let headers = mcp_common_headers(
      self.configured_headers,
      self.protocol_version_value.val,
      Some(session_id),
    )
    ignore(
      self.http_transport.fetch(
        @provider_utils.HttpRequest::delete(url=self.url, headers~),
      ) catch {
        _ => @provider_utils.HttpResponse::text(status_code=599, body="")
      },
    )
    self.set_session_id(None)
  }
  self.started.val = false
}

///|
pub impl MCPTransport for HttpMCPTransport with fn protocol_version(self) {
  self.protocol_version_value.val
}

///|
pub impl MCPTransport for HttpMCPTransport with fn set_protocol_version(
  self,
  version,
) {
  self.protocol_version_value.val = Some(version)
}

///|
fn resolve_same_origin_endpoint(
  base : String,
  endpoint : String,
) -> String raise MCPClientError {
  if endpoint.has_prefix("http://") || endpoint.has_prefix("https://") {
    guard @provider_utils.url_authority(endpoint) ==
      @provider_utils.url_authority(base) else {
      raise mcp_error("MCP SSE endpoint origin does not match server origin")
    }
    return endpoint
  }
  let authority = @provider_utils.url_authority(base).unwrap_or_else(() => {
    raise mcp_error("MCP SSE URL must be absolute")
  })
  let scheme = if base.has_prefix("https://") { "https" } else { "http" }
  if endpoint.has_prefix("/") {
    "\{scheme}://\{authority}\{endpoint}"
  } else {
    let origin = "\{scheme}://\{authority}"
    let suffix = base[origin.length():].to_owned()
    let parts = suffix.split("/").to_array()
    let directory = if parts.length() <= 1 {
      "/"
    } else {
      "/" + parts[:parts.length() - 1].join("/") + "/"
    }
    origin + directory + endpoint
  }
}

///|
fn decode_sse_endpoint(
  text : String,
  url : String,
) -> String raise MCPClientError {
  let mut event_name = ""
  let data_lines : Array[String] = []
  for raw in text.split("\n") {
    let line = raw.to_owned().strip_suffix("\r").unwrap_or(raw.to_owned())
    if line.trim() == "" {
      if event_name == "endpoint" && data_lines.length() > 0 {
        return resolve_same_origin_endpoint(url, data_lines.join("\n"))
      }
      event_name = ""
      data_lines.clear()
    } else if line.has_prefix("event:") {
      event_name = line[6:].to_owned().trim().to_owned()
    } else if line.has_prefix("data:") {
      data_lines.push(line[5:].to_owned().trim().to_owned())
    }
  }
  if event_name == "endpoint" && data_lines.length() > 0 {
    return resolve_same_origin_endpoint(url, data_lines.join("\n"))
  }
  raise mcp_error("MCP SSE stream did not provide an endpoint event")
}

///|
/// Legacy MCP HTTP+SSE transport.
///
/// The initial SSE response is buffered until the endpoint event is known.
/// Subsequent POST responses may contain SSE or JSON frames, which keeps this
/// transport usable with finite test servers and command gateways.
pub struct SseMCPTransport {
  url : String
  configured_headers : Map[String, String]
  http_transport : &@provider_utils.HttpTransport
  priv endpoint : Ref[String?]
  priv protocol_version_value : Ref[String?]
  priv started : Ref[Bool]
}

///|
/// Construct a legacy SSE MCP transport.
pub fn SseMCPTransport::new(
  url~ : String,
  headers? : Map[String, String] = Map([]),
  http_transport? : &@provider_utils.HttpTransport,
) -> SseMCPTransport {
  {
    url,
    configured_headers: @provider_utils.copy_headers(headers),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
    endpoint: Ref(None),
    protocol_version_value: Ref(None),
    started: Ref(false),
  }
}

///|
/// Endpoint announced by the SSE server.
pub fn SseMCPTransport::endpoint(self : SseMCPTransport) -> String? {
  self.endpoint.val
}

///|
pub impl MCPTransport for SseMCPTransport with fn start(self) {
  guard !self.started.val else {
    raise mcp_error("MCP SSE transport already started")
  }
  let headers = mcp_common_headers(
    self.configured_headers,
    self.protocol_version_value.val,
    None,
  )
  headers["Accept"] = "text/event-stream"
  let response = self.http_transport.fetch(
    @provider_utils.HttpRequest::get(url=self.url, headers~),
  ) catch {
    error =>
      raise MCPClientError::new(
        message="MCP SSE transport failed to connect",
        url=self.url,
        cause=@debug.to_string(error),
      )
  }
  let body = response.body_text() catch {
    error =>
      raise MCPClientError::new(
        message="MCP SSE endpoint response was not UTF-8",
        status_code=response.status_code,
        url=self.url,
        cause=@debug.to_string(error),
      )
  }
  guard response.is_success() else {
    raise MCPClientError::new(
      message="MCP SSE transport returned HTTP \{response.status_code} \{response.reason}",
      status_code=response.status_code,
      url=self.url,
      response_body=body,
    )
  }
  self.endpoint.val = Some(decode_sse_endpoint(body, self.url))
  self.started.val = true
}

///|
pub impl MCPTransport for SseMCPTransport with fn send(self, message, options) {
  @provider.check_cancellation(options.cancellation_token)
  guard self.started.val && self.endpoint.val is Some(endpoint) else {
    raise mcp_error("MCP SSE transport is not connected")
  }
  let headers = mcp_common_headers(
    self.configured_headers,
    self.protocol_version_value.val,
    None,
  )
  headers["Content-Type"] = "application/json"
  headers["Accept"] = "application/json, text/event-stream"
  let response = self.http_transport.fetch(
    @provider_utils.HttpRequest::post(
      url=endpoint,
      headers~,
      body=@utf8.encode(message.to_json().stringify()),
    ),
  ) catch {
    error =>
      raise MCPClientError::new(
        message="MCP SSE transport POST failed",
        url=endpoint,
        cause=@debug.to_string(error),
      )
  }
  let body = response.body_text() catch {
    error =>
      raise MCPClientError::new(
        message="MCP SSE transport response was not UTF-8",
        status_code=response.status_code,
        url=endpoint,
        cause=@debug.to_string(error),
      )
  }
  guard response.is_success() else {
    raise MCPClientError::new(
      message="MCP SSE transport returned HTTP \{response.status_code} \{response.reason}",
      status_code=response.status_code,
      url=endpoint,
      response_body=body,
    )
  }
  if response.status_code == 202 || body.trim() == "" {
    []
  } else {
    decode_http_mcp_messages(
      body,
      header_value(response.headers, "content-type").unwrap_or(
        "application/json",
      ),
    )
  }
}

///|
pub impl MCPTransport for SseMCPTransport with fn close(self, options) {
  @provider.check_cancellation(options.cancellation_token)
  self.started.val = false
  self.endpoint.val = None
}

///|
pub impl MCPTransport for SseMCPTransport with fn protocol_version(self) {
  self.protocol_version_value.val
}

///|
pub impl MCPTransport for SseMCPTransport with fn set_protocol_version(
  self,
  version,
) {
  self.protocol_version_value.val = Some(version)
}

///|
/// Configuration for a persistent MCP stdio child process.
pub(all) struct StdioConfig {
  command : String
  args : Array[String]
  env : Map[String, String]
  inherit_env : Bool
  cwd : String?
}

///|
/// Construct stdio server configuration.
pub fn StdioConfig::new(
  command~ : String,
  args? : Array[String] = [],
  env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  cwd? : String,
) -> StdioConfig {
  { command, args, env, inherit_env, cwd }
}

///|
/// Persistent newline-delimited JSON MCP transport.
pub struct StdioMCPTransport {
  config : StdioConfig
  priv stdin_writer : Ref[@process.WriteToProcess?]
  priv stdout_reader : Ref[@process.ReadFromProcess?]
  priv pid : Ref[Int?]
  priv protocol_version_value : Ref[String?]
}

///|
/// Construct a persistent MCP stdio transport.
pub fn StdioMCPTransport::new(config : StdioConfig) -> StdioMCPTransport {
  {
    config,
    stdin_writer: Ref(None),
    stdout_reader: Ref(None),
    pid: Ref(None),
    protocol_version_value: Ref(None),
  }
}

///|
pub impl MCPTransport for StdioMCPTransport with fn start(self) {
  guard self.pid.val is None else {
    raise mcp_error("StdioMCPTransport already started")
  }
  let (child_stdin, writer) = @process.write_to_process() catch {
    error =>
      raise MCPClientError::new(
        message="Failed to create MCP stdin pipe",
        cause=@debug.to_string(error),
      )
  }
  let (reader, child_stdout) = @process.read_from_process() catch {
    error => {
      writer.close()
      raise MCPClientError::new(
        message="Failed to create MCP stdout pipe",
        cause=@debug.to_string(error),
      )
    }
  }
  let pid = try {
    match self.config.cwd {
      Some(cwd) =>
        @process.spawn_orphan(
          self.config.command,
          self.config.args,
          extra_env=self.config.env,
          inherit_env=self.config.inherit_env,
          stdin=child_stdin,
          stdout=child_stdout,
          cwd~,
          no_console_window=true,
        )
      None =>
        @process.spawn_orphan(
          self.config.command,
          self.config.args,
          extra_env=self.config.env,
          inherit_env=self.config.inherit_env,
          stdin=child_stdin,
          stdout=child_stdout,
          no_console_window=true,
        )
    }
  } catch {
    error => {
      writer.close()
      reader.close()
      raise MCPClientError::new(
        message="Failed to start MCP stdio process",
        cause=@debug.to_string(error),
      )
    }
  }
  self.stdin_writer.val = Some(writer)
  self.stdout_reader.val = Some(reader)
  self.pid.val = Some(pid)
}

///|
pub impl MCPTransport for StdioMCPTransport with fn send(self, message, options) {
  @provider.check_cancellation(options.cancellation_token)
  guard self.stdin_writer.val is Some(writer) &&
    self.stdout_reader.val is Some(reader) else {
    raise mcp_error("StdioMCPTransport is not connected")
  }
  writer.write(message.to_json().stringify() + "\n") catch {
    error =>
      raise MCPClientError::new(
        message="Failed to write MCP stdio request",
        cause=@debug.to_string(error),
      )
  }
  let messages : Array[JSONRPCMessage] = []
  for ;; {
    @provider.check_cancellation(options.cancellation_token)
    let line = reader.read_until("\n") catch {
      error =>
        raise MCPClientError::new(
          message="Failed to read MCP stdio response",
          cause=@debug.to_string(error),
        )
    }
    guard line is Some(value) else {
      raise mcp_error("MCP stdio process closed before responding")
    }
    let frame = value.trim(chars="\r\n").to_owned()
    if frame == "" {
      continue
    }
    let decoded = parse_json_rpc_message(frame)
    messages.push(decoded)
    let done = match (message, decoded) {
      (JSONRPCRequest(id=request_id, ..), JSONRPCResponse(id=response_id, ..)) =>
        request_id == response_id
      (JSONRPCRequest(id=request_id, ..), JSONRPCError(id=response_id, ..)) =>
        request_id == response_id
      (JSONRPCNotification(..), _) => true
      _ => false
    }
    if done {
      return messages
    }
  }
}

///|
pub impl MCPTransport for StdioMCPTransport with fn close(self, options) {
  @provider.check_cancellation(options.cancellation_token)
  if self.stdin_writer.val is Some(writer) {
    writer.close()
  }
  self.stdin_writer.val = None
  if self.stdout_reader.val is Some(reader) {
    reader.close()
  }
  self.stdout_reader.val = None
  self.pid.val = None
}

///|
pub impl MCPTransport for StdioMCPTransport with fn protocol_version(self) {
  self.protocol_version_value.val
}

///|
pub impl MCPTransport for StdioMCPTransport with fn set_protocol_version(
  self,
  version,
) {
  self.protocol_version_value.val = Some(version)
}

///|
/// Compatibility constructor matching AI SDK's experimental stdio export.
pub fn experimental_stdio_mcp_transport(
  config : StdioConfig,
) -> StdioMCPTransport {
  StdioMCPTransport::new(config)
}

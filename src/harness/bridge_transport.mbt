///|
/// WebSocket-backed harness bridge connection.
priv struct WebSocketHarnessV1BridgeConnection {
  connection : &@provider_utils.WebSocketConnection
  closed : Ref[Bool]
}

///|
impl HarnessV1BridgeConnection for WebSocketHarnessV1BridgeConnection with fn send(
  self,
  message,
) {
  guard !self.closed.val else { fail("Harness WebSocket connection is closed") }
  self.connection.send_text(message)
}

///|
impl HarnessV1BridgeConnection for WebSocketHarnessV1BridgeConnection with fn receive(
  self,
) {
  guard !self.closed.val else { return None }
  match self.connection.receive() {
    @provider_utils.WebSocketText(text) => Some(text)
    @provider_utils.WebSocketBinary(_) =>
      fail("Harness bridge requires text WebSocket frames")
    @provider_utils.WebSocketClosed(..) => {
      self.closed.val = true
      None
    }
  }
}

///|
impl HarnessV1BridgeConnection for WebSocketHarnessV1BridgeConnection with fn close(
  self,
) {
  if !self.closed.val {
    self.closed.val = true
    self.connection.close()
  }
}

///|
/// Connect to a harness bridge over WebSocket.
pub async fn connect_harness_v1_websocket(
  url : String,
  token? : String,
  headers? : Map[String, String] = Map([]),
  connector? : &@provider_utils.WebSocketConnector = @provider_utils.native_websocket_connector(),
) -> &HarnessV1BridgeConnection {
  let request_headers = @provider_utils.copy_headers(headers)
  if token is Some(value) && value != "" {
    request_headers["Authorization"] = "Bearer " + value
  }
  let connection = connector.connect(url, [], request_headers)
  WebSocketHarnessV1BridgeConnection::{ connection, closed: Ref(false) }
  as &HarnessV1BridgeConnection
}

///|
/// Configuration for a persistent NDJSON bridge child process.
pub(all) struct HarnessV1StdioConfig {
  command : String
  args : Array[String]
  env : Map[String, String]
  inherit_env : Bool
  cwd : String?
}

///|
/// Construct a persistent stdio bridge configuration.
pub fn HarnessV1StdioConfig::new(
  command~ : String,
  args? : Array[String] = [],
  env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  cwd? : String,
) -> HarnessV1StdioConfig {
  { command, args: args.copy(), env, inherit_env, cwd }
}

///|
/// Persistent newline-delimited JSON bridge connection.
priv struct StdioHarnessV1BridgeConnection {
  writer : @process.WriteToProcess
  reader : @process.ReadFromProcess
  closed : Ref[Bool]
}

///|
impl HarnessV1BridgeConnection for StdioHarnessV1BridgeConnection with fn send(
  self,
  message,
) {
  guard !self.closed.val else { fail("Harness stdio connection is closed") }
  self.writer.write(message + "\n")
}

///|
impl HarnessV1BridgeConnection for StdioHarnessV1BridgeConnection with fn receive(
  self,
) {
  guard !self.closed.val else { return None }
  for ;; {
    match self.reader.read_until("\n") {
      None => {
        self.closed.val = true
        return None
      }
      Some(line) => {
        let frame = line.trim(chars="\r\n").to_owned()
        if frame != "" {
          return Some(frame)
        }
      }
    }
  }
}

///|
impl HarnessV1BridgeConnection for StdioHarnessV1BridgeConnection with fn close(
  self,
) {
  if !self.closed.val {
    self.closed.val = true
    self.writer.close()
    self.reader.close()
  }
}

///|
/// Spawn and connect to a persistent NDJSON bridge process.
pub async fn connect_harness_v1_stdio(
  config : HarnessV1StdioConfig,
) -> &HarnessV1BridgeConnection raise HarnessError {
  let (child_stdin, writer) = @process.write_to_process() catch {
    error =>
      raise HarnessError(
        message="Failed to create harness bridge stdin pipe",
        cause=Some(@debug.to_string(error)),
      )
  }
  let (reader, child_stdout) = @process.read_from_process() catch {
    error => {
      writer.close()
      raise HarnessError(
        message="Failed to create harness bridge stdout pipe",
        cause=Some(@debug.to_string(error)),
      )
    }
  }
  ignore(
    match config.cwd {
      Some(cwd) =>
        @process.spawn_orphan(
          config.command,
          config.args,
          extra_env=config.env,
          inherit_env=config.inherit_env,
          stdin=child_stdin,
          stdout=child_stdout,
          cwd~,
          no_console_window=true,
        )
      None =>
        @process.spawn_orphan(
          config.command,
          config.args,
          extra_env=config.env,
          inherit_env=config.inherit_env,
          stdin=child_stdin,
          stdout=child_stdout,
          no_console_window=true,
        )
    },
  ) catch {
    error => {
      writer.close()
      reader.close()
      raise HarnessError(
        message="Failed to start harness bridge process",
        cause=Some(@debug.to_string(error)),
      )
    }
  }
  StdioHarnessV1BridgeConnection::{ writer, reader, closed: Ref(false) }
  as &HarnessV1BridgeConnection
}

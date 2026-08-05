///|
/// One decoded WebSocket message or terminal close notification.
pub(all) enum WebSocketReceive {
  WebSocketText(String)
  WebSocketBinary(Bytes)
  WebSocketClosed(code~ : Int?, reason~ : String?)
} derive(Debug, Eq)

///|
/// Runtime-independent WebSocket connection used by provider protocols.
/// Implementations must serialize concurrent writes.
pub(open) trait WebSocketConnection {
  async fn send_text(Self, String) -> Unit
  async fn send_binary(Self, Bytes) -> Unit
  async fn receive(Self) -> WebSocketReceive
  async fn send_close(Self, Int, String?) -> Unit
  fn close(Self) -> Unit
}

///|
/// Injectable WebSocket connector. This is the MoonBit counterpart of AI
/// SDK provider-utils' `WebSocketConstructor` boundary.
pub(open) trait WebSocketConnector {
  async fn connect(Self, String, Array[String], Map[String, String]) -> &WebSocketConnection
}

///|
/// Convert an HTTP(S) provider URL to its WebSocket counterpart.
pub fn to_websocket_url(url : String) -> String {
  if url.has_prefix("https://") {
    let rest = url[8:]
    "wss://\{rest}"
  } else if url.has_prefix("http://") {
    let rest = url[7:]
    "ws://\{rest}"
  } else {
    url
  }
}

///|
/// AI SDK-style camel-case alias.
pub fn toWebSocketUrl(url : String) -> String {
  to_websocket_url(url)
}

///|
fn websocket_close_code_to_int(code : @websocket.CloseCode) -> Int {
  match code {
    Normal => 1000
    GoingAway => 1001
    ProtocolError => 1002
    UnsupportedData => 1003
    Abnormal => 1006
    InvalidFramePayload => 1007
    PolicyViolation => 1008
    MessageTooBig => 1009
    MissingExtension => 1010
    InternalError => 1011
    Other(value) => value.to_int()
  }
}

///|
fn websocket_close_code_from_int(code : Int) -> @websocket.CloseCode {
  match code {
    1000 => Normal
    1001 => GoingAway
    1002 => ProtocolError
    1003 => UnsupportedData
    1006 => Abnormal
    1007 => InvalidFramePayload
    1008 => PolicyViolation
    1009 => MessageTooBig
    1010 => MissingExtension
    1011 => InternalError
    value => Other(value.to_uint16())
  }
}

///|
priv struct NativeWebSocketConnection {
  connection : @websocket.Conn
}

///|
impl WebSocketConnection for NativeWebSocketConnection with fn send_text(
  self,
  text,
) {
  self.connection.send_text(text)
}

///|
impl WebSocketConnection for NativeWebSocketConnection with fn send_binary(
  self,
  data,
) {
  self.connection.send_binary(data)
}

///|
impl WebSocketConnection for NativeWebSocketConnection with fn receive(self) {
  let message = self.connection.recv() catch {
    @websocket.ConnectionClosed(code, reason) =>
      return WebSocketClosed(
        code=Some(websocket_close_code_to_int(code)),
        reason~,
      )
    error => raise error
  }
  let data = message.read_all()
  match message.kind {
    Text => WebSocketText(data.text())
    Binary => WebSocketBinary(data.binary())
  }
}

///|
impl WebSocketConnection for NativeWebSocketConnection with fn send_close(
  self,
  code,
  reason,
) {
  self.connection.send_close(code=websocket_close_code_from_int(code), reason?)
}

///|
impl WebSocketConnection for NativeWebSocketConnection with fn close(self) {
  self.connection.close()
}

///|
/// Connector backed by `moonbitlang/async/websocket`, including native TLS.
pub struct NativeWebSocketConnector {}

///|
/// Construct the built-in native WebSocket connector.
pub fn NativeWebSocketConnector::new() -> NativeWebSocketConnector {
  NativeWebSocketConnector::{  }
}

///|
impl WebSocketConnector for NativeWebSocketConnector with fn connect(
  _self,
  url,
  protocols,
  headers,
) {
  let handshake_headers = copy_headers(headers)
  if protocols.length() > 0 {
    handshake_headers["Sec-WebSocket-Protocol"] = protocols.join(", ")
  }
  let connection = @websocket.connect(url, headers=handshake_headers)
  NativeWebSocketConnection::{ connection, } as &WebSocketConnection
}

///|
/// Return the default native connector as an injectable trait object.
pub fn native_websocket_connector() -> &WebSocketConnector {
  NativeWebSocketConnector::new()
}

///|
fn mcp_header_value_is_plain_ascii(value : String) -> Bool {
  let bytes = @utf8.encode(value)
  for byte in bytes {
    let code = byte.to_int()
    if code != 0x09 && (code < 0x20 || code > 0x7e) {
      return false
    }
  }
  true
}

///|
fn mcp_header_value_is_base64_sentinel(value : String) -> Bool {
  value.has_prefix("=?base64?") && value.has_suffix("?=")
}

///|
/// Encode an MCP header value.
///
/// Plain printable ASCII passes through; anything else (non-ASCII,
/// leading/trailing whitespace, or values that already look like the
/// sentinel) is encoded as an RFC 2231-style `=?base64?...?=` sentinel so
/// header integrity survives arbitrary server names and resource URIs.
pub fn encode_mcp_header_value(value : String) -> String {
  if mcp_header_value_is_plain_ascii(value) &&
    value.trim().to_owned() == value &&
    !mcp_header_value_is_base64_sentinel(value) {
    return value
  }
  "=?base64?\{@base64.encode(@utf8.encode(value))}?="
}

///|
/// Standard per-request MCP headers (AI SDK Mcp-Method/Mcp-Name).
///
/// Requests are tagged with the invoked method and, for methods that target
/// a named resource, the target name or URI. Servers use these for routing,
/// rate limiting, and audit without parsing request bodies.
fn mcp_standard_request_headers(
  message : JSONRPCMessage,
) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  let method_name = match message {
    JSONRPCRequest(method_name~, ..) => method_name
    _ => return headers
  }
  headers["Mcp-Method"] = method_name
  let params : Map[String, Json]? = match message {
    JSONRPCRequest(params=Some(Object(values)), ..) => Some(values)
    _ => None
  }
  let name : Json? = match (method_name, params) {
    ("resources/read", Some(values)) => values.get("uri")
    ("tools/call", Some(values)) | ("prompts/get", Some(values)) =>
      values.get("name")
    _ => None
  }
  match name {
    Some(String(value)) => headers["Mcp-Name"] = encode_mcp_header_value(value)
    _ => ()
  }
  headers
}

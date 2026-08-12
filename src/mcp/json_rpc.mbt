///|
/// JSON-RPC request identifiers accepted by MCP.
pub(all) enum JSONRPCId {
  JSONRPCStringId(String)
  JSONRPCNumberId(Int)
} derive(Debug, Eq)

///|
/// A JSON-RPC 2.0 application error.
pub(all) struct JSONRPCErrorData {
  code : Int
  message : String
  data : Json?
} derive(Debug, Eq)

///|
/// JSON-RPC messages exchanged by MCP transports.
pub(all) enum JSONRPCMessage {
  JSONRPCRequest(id~ : JSONRPCId, method_name~ : String, params~ : Json?)
  JSONRPCNotification(method_name~ : String, params~ : Json?)
  JSONRPCResponse(id~ : JSONRPCId, result~ : Json)
  JSONRPCError(id~ : JSONRPCId, error~ : JSONRPCErrorData)
} derive(Debug, Eq)

///|
/// Construct a JSON-RPC request.
pub fn JSONRPCMessage::request(
  id~ : JSONRPCId,
  method_name~ : String,
  params? : Json,
) -> JSONRPCMessage {
  JSONRPCRequest(id~, method_name~, params~)
}

///|
/// Construct a JSON-RPC notification.
pub fn JSONRPCMessage::notification(
  method_name~ : String,
  params? : Json,
) -> JSONRPCMessage {
  JSONRPCNotification(method_name~, params~)
}

///|
/// Construct a successful JSON-RPC response.
pub fn JSONRPCMessage::response(
  id~ : JSONRPCId,
  result? : Json = Json::empty_object(),
) -> JSONRPCMessage {
  JSONRPCResponse(id~, result~)
}

///|
/// Construct a failed JSON-RPC response.
pub fn JSONRPCMessage::error(
  id~ : JSONRPCId,
  code~ : Int,
  message~ : String,
  data? : Json,
) -> JSONRPCMessage {
  JSONRPCError(id~, error={ code, message, data })
}

///|
fn json_rpc_id_to_json(id : JSONRPCId) -> Json {
  match id {
    JSONRPCStringId(value) => Json::string(value)
    JSONRPCNumberId(value) => Json::number(value.to_double())
  }
}

///|
fn decode_json_rpc_id(value : Json) -> JSONRPCId raise MCPClientError {
  match value {
    String(value) => JSONRPCStringId(value)
    Number(value, ..) => JSONRPCNumberId(value.to_int())
    _ => raise mcp_error("JSON-RPC id must be a string or integer")
  }
}

///|
fn validate_json_rpc_params(params : Json?) -> Unit raise MCPClientError {
  match params {
    None | Some(Object(_)) | Some(Array(_)) => ()
    Some(_) => raise mcp_error("JSON-RPC params must be an object or array")
  }
}

///|
/// Encode a typed JSON-RPC message.
pub fn JSONRPCMessage::to_json(self : JSONRPCMessage) -> Json {
  match self {
    JSONRPCRequest(id~, method_name~, params~) => {
      let fields : Map[String, Json] = Map([
        ("jsonrpc", Json::string("2.0")),
        ("id", json_rpc_id_to_json(id)),
        ("method", Json::string(method_name)),
      ])
      if params is Some(value) {
        fields["params"] = value
      }
      Json::object(fields)
    }
    JSONRPCNotification(method_name~, params~) => {
      let fields : Map[String, Json] = Map([
        ("jsonrpc", Json::string("2.0")),
        ("method", Json::string(method_name)),
      ])
      if params is Some(value) {
        fields["params"] = value
      }
      Json::object(fields)
    }
    JSONRPCResponse(id~, result~) =>
      (
        { "jsonrpc": "2.0", "id": json_rpc_id_to_json(id), "result": result } :
        Json)
    JSONRPCError(id~, error~) => {
      let error_fields : Map[String, Json] = Map([
        ("code", Json::number(error.code.to_double())),
        ("message", Json::string(error.message)),
      ])
      if error.data is Some(value) {
        error_fields["data"] = value
      }
      (
        {
          "jsonrpc": "2.0",
          "id": json_rpc_id_to_json(id),
          "error": Json::object(error_fields),
        } : Json)
    }
  }
}

///|
/// Validate and decode a strict JSON-RPC 2.0 message.
pub fn validate_json_rpc_message(
  message : Json,
) -> JSONRPCMessage raise MCPClientError {
  guard message is Object(fields) else {
    raise mcp_error("JSON-RPC message must be an object")
  }
  guard fields.get("jsonrpc") is Some(String("2.0")) else {
    raise mcp_error("JSON-RPC message must use version 2.0")
  }
  let id = fields.get("id")
  let method_value = fields.get("method")
  let result = fields.get("result")
  let error = fields.get("error")
  match (id, method_value, result, error) {
    (Some(id), Some(String(method_name)), None, None) => {
      let params = fields.get("params")
      validate_json_rpc_params(params)
      JSONRPCRequest(id=decode_json_rpc_id(id), method_name~, params~)
    }
    (None, Some(String(method_name)), None, None) => {
      let params = fields.get("params")
      validate_json_rpc_params(params)
      JSONRPCNotification(method_name~, params~)
    }
    (Some(id), None, Some(result), None) =>
      JSONRPCResponse(id=decode_json_rpc_id(id), result~)
    (Some(id), None, None, Some(Object(error_fields))) => {
      guard error_fields.get("code") is Some(Number(code, ..)) &&
        error_fields.get("message") is Some(String(message)) else {
        raise mcp_error("JSON-RPC error must contain integer code and message")
      }
      JSONRPCError(id=decode_json_rpc_id(id), error={
        code: code.to_int(),
        message,
        data: error_fields.get("data"),
      })
    }
    _ => raise mcp_error("Invalid or ambiguous JSON-RPC message")
  }
}

///|
/// AI SDK-style spelling for `validate_json_rpc_message`.
pub fn validateJSONRPCMessage(
  message : Json,
) -> JSONRPCMessage raise MCPClientError {
  validate_json_rpc_message(message)
}

///|
/// Parse and validate one serialized JSON-RPC message.
pub fn parse_json_rpc_message(
  text : String,
) -> JSONRPCMessage raise MCPClientError {
  let value = @json.parse(text) catch {
    error =>
      raise MCPClientError::new(
        message="Failed to parse JSON-RPC message",
        cause=@debug.to_string(error),
      )
  }
  validate_json_rpc_message(value)
}

///|
/// AI SDK-style spelling for `parse_json_rpc_message`.
pub fn parseJSONRPCMessage(
  text : String,
) -> JSONRPCMessage raise MCPClientError {
  parse_json_rpc_message(text)
}

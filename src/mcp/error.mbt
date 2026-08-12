///|
/// An MCP protocol, client, or transport operation failed.
pub(all) suberror MCPClientError {
  MCPClientError(
    message~ : String,
    code~ : Int?,
    data~ : Json?,
    status_code~ : Int?,
    url~ : String?,
    response_body~ : String?,
    cause~ : String?
  )
} derive(Debug, Eq)

///|
/// Construct an MCP client error with optional protocol and HTTP diagnostics.
pub fn MCPClientError::new(
  message~ : String,
  code? : Int,
  data? : Json,
  status_code? : Int,
  url? : String,
  response_body? : String,
  cause? : String,
) -> MCPClientError {
  MCPClientError(
    message~,
    code~,
    data~,
    status_code~,
    url~,
    response_body~,
    cause~,
  )
}

///|
/// Return the human-readable MCP error message.
pub fn MCPClientError::message(self : MCPClientError) -> String {
  match self {
    MCPClientError(message~, ..) => message
  }
}

///|
/// An OAuth operation for an MCP server failed.
pub(all) suberror MCPClientOAuthError {
  MCPClientOAuthError(message~ : String, cause~ : String?)
} derive(Debug, Eq)

///|
/// The MCP server requires authorization.
pub(all) suberror UnauthorizedError {
  UnauthorizedError(message~ : String)
} derive(Debug, Eq)

///|
fn mcp_error(message : String) -> MCPClientError {
  MCPClientError::new(message~)
}

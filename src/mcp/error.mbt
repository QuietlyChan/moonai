///|
/// An MCP protocol, client, or transport operation failed.
#derive(Debug, Eq)
pub(all) suberror MCPClientError {
  MCPClientError(
    message~ : String,
    code~ : Int32?,
    data~ : Json?,
    status_code~ : Int32?,
    url~ : String?,
    response_body~ : String?,
    cause~ : String?
  )
}

///|
/// Construct an MCP client error with optional protocol and HTTP diagnostics.
pub fn MCPClientError::new(
  message~ : String,
  code? : Int32,
  data? : Json,
  status_code? : Int32,
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
#derive(Debug, Eq)
pub(all) suberror MCPClientOAuthError {
  MCPClientOAuthError(message~ : String, cause~ : String?)
}

///|
/// The MCP server requires authorization.
#derive(Debug, Eq)
pub(all) suberror UnauthorizedError {
  UnauthorizedError(message~ : String)
}

///|
fn mcp_error(message : String) -> MCPClientError {
  MCPClientError::new(message~)
}

///|
pub extend MCPClientError with Debug::{to_repr}

///|
pub extend MCPClientError with Eq::{not_equal, equal}

///|
pub extend MCPClientOAuthError with Debug::{to_repr}

///|
pub extend MCPClientOAuthError with Eq::{not_equal, equal}

///|
pub extend UnauthorizedError with Debug::{to_repr}

///|
pub extend UnauthorizedError with Eq::{not_equal, equal}

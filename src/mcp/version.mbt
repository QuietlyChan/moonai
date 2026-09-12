///|
/// MoonAI MCP package version.
pub const VERSION : String = "0.1.0"

///|
/// Latest MCP protocol version advertised by the client.
pub const LATEST_PROTOCOL_VERSION : String = "2026-07-28"

///|
/// Previous protocol generation still understood by this implementation.
pub const LATEST_LEGACY_PROTOCOL_VERSION : String = "2025-11-25"

///|
/// Protocol versions understood by this implementation, newest first.
pub let supported_protocol_versions : Array[String] = [
  LATEST_PROTOCOL_VERSION,
  LATEST_LEGACY_PROTOCOL_VERSION,
  "2025-06-18",
  "2025-03-26",
  "2024-11-05",
]

///|
/// Return an independent list of supported MCP protocol versions.
pub fn supportedProtocolVersions() -> Array[String] {
  supported_protocol_versions.copy()
}

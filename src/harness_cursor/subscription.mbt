///|
/// Version of the Moonai harness-cursor subpackage.
pub const VERSION : String = "0.1.0"

///|
/// Resolve the Cursor CLI auth.json path for the given platform layout
/// (Windows %APPDATA%, Linux XDG config, macOS ~/.cursor).
pub fn resolve_cursor_auth_path(
  home_directory~ : String,
  appdata~ : String?,
  xdg_config_home~ : String?,
) -> String {
  // Windows layout first: %APPDATA%\Cursor\auth.json
  if appdata is Some(appdata) {
    return @provider_utils.append_path(appdata, "Cursor/auth.json")
  }
  // Linux layout: $XDG_CONFIG_HOME/cursor/auth.json
  if xdg_config_home is Some(xdg) {
    return @provider_utils.append_path(xdg, "cursor/auth.json")
  }
  // macOS / generic fallback: ~/.cursor/auth.json
  @provider_utils.append_path(home_directory, ".cursor/auth.json")
}

///|
/// Parse an access token out of the Cursor auth.json payload. Returns None
/// when the payload is not an object or carries no string accessToken.
pub fn parse_cursor_access_token(payload~ : Json) -> String? {
  match payload {
    Object(fields) =>
      match fields.get("accessToken") {
        Some(String(token)) => Some(token)
        _ => None
      }
    _ => None
  }
}

///|
/// Extract the JWT `exp` claim (epoch seconds) from an access token. Returns
/// None when the token is not a decodable JWT with a numeric exp.
pub fn cursor_jwt_expires_at(access_token~ : String) -> Int? raise {
  let segments = access_token.split(".").to_array()
  guard segments.length() >= 2 else { return None }
  let payload_segment = segments[1].to_owned()
  let normalized = StringBuilder()
  for ch in payload_segment {
    match ch {
      '-' => normalized.write_char('+')
      '_' => normalized.write_char('/')
      c => normalized.write_char(c)
    }
  }
  while normalized.to_string().length() % 4 != 0 {
    normalized.write_string("=")
  }
  let payload_bytes = @base64.decode(normalized.to_string())
  let payload_json = @utf8.decode(payload_bytes)
  match @json.parse(payload_json) {
    { "exp": Number(exp, ..), .. } => Some(exp.to_int())
    _ => None
  }
}

///|
/// Whether a token expiring at `expires_at` (epoch seconds) is within five
/// minutes of expiry relative to `now`.
pub fn cursor_token_expiring_soon(expires_at~ : Int, now~ : Int) -> Bool {
  expires_at - now < 300
}

///|
/// Decide whether the native Cursor subscription should be resolved: only
/// when the auth mode is not gateway-only, no direct credential is present,
/// and the environment carries no AI Gateway key.
pub fn should_resolve_cursor_native_subscription(
  ai_gateway_auth~ : Bool,
  has_direct_credential~ : Bool,
) -> Bool {
  !ai_gateway_auth && !has_direct_credential
}

///|
/// Parse the Cursor subscription access token from raw auth.json content.
/// `credential_store = Some("memory")` disables resolution entirely,
/// matching upstream. File reading itself is the caller's responsibility
/// (native filesystem access lives in the host integration layer).
pub fn read_cursor_subscription(
  auth_json~ : String?,
  credential_store~ : String?,
) -> String? {
  if credential_store is Some(store) && store == "memory" {
    return None
  }
  match auth_json {
    Some(content) => {
      let parsed = @json.parse(content) catch { _ => return None }
      parse_cursor_access_token(payload=parsed)
    }
    None => None
  }
}

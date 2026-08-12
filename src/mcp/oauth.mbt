///|
/// OAuth 2.1 tokens used by MCP transports.
pub(all) struct OAuthTokens {
  access_token : String
  id_token : String?
  token_type : String
  expires_in : Int?
  scope : String?
  refresh_token : String?
  authorization_server : String?
  token_endpoint : String?
} derive(Debug, Eq)

///|
/// OAuth dynamic client registration result.
pub(all) struct OAuthClientInformation {
  client_id : String
  client_secret : String?
  client_id_issued_at : Int?
  client_secret_expires_at : Int?
  authorization_server : String?
  token_endpoint : String?
} derive(Debug, Eq)

///|
/// OAuth client metadata. Extension fields are retained in `raw`.
pub(all) struct OAuthClientMetadata {
  redirect_uris : Array[String]
  token_endpoint_auth_method : String?
  grant_types : Array[String]
  response_types : Array[String]
  client_name : String?
  scope : String?
  raw : Json
} derive(Debug, Eq)

///|
/// Authorization server URLs pinned to stored credentials.
pub(all) struct OAuthAuthorizationServerInformation {
  authorization_server_url : String
  token_endpoint : String
} derive(Debug, Eq)

///|
/// OAuth authorization server discovery metadata.
pub(all) struct OAuthAuthorizationServerMetadata {
  issuer : String
  authorization_endpoint : String
  token_endpoint : String
  registration_endpoint : String?
  response_types_supported : Array[String]
  grant_types_supported : Array[String]
  code_challenge_methods_supported : Array[String]
  token_endpoint_auth_methods_supported : Array[String]
  raw : Json
} derive(Debug, Eq)

///|
/// OAuth protected-resource metadata for an MCP server.
pub(all) struct OAuthProtectedResourceMetadata {
  resource : String
  authorization_servers : Array[String]
  scopes_supported : Array[String]
  raw : Json
} derive(Debug, Eq)

///|
/// Result of starting or completing an MCP OAuth flow.
pub(all) enum AuthResult {
  Authorized
  Redirect
} derive(Debug, Eq)

///|
/// URL and verifier generated for an OAuth authorization redirect.
pub(all) struct OAuthAuthorizationStart {
  authorization_url : String
  code_verifier : String
} derive(Debug, Eq)

///|
/// Storage and interaction boundary used by the OAuth flow.
pub(open) trait OAuthClientProvider {
  async fn tokens(Self) -> OAuthTokens?
  async fn save_tokens(Self, OAuthTokens) -> Unit
  async fn redirect_to_authorization(Self, String) -> Unit
  async fn save_code_verifier(Self, String) -> Unit
  async fn code_verifier(Self) -> String
  fn redirect_url(Self) -> String
  fn client_metadata(Self) -> OAuthClientMetadata
  async fn client_information(Self) -> OAuthClientInformation?
  async fn save_client_information(Self, OAuthClientInformation) -> Unit
  async fn invalidate_credentials(Self, String) -> Unit
}

///|
fn decode_string_array(value : Json?) -> Array[String] {
  let result : Array[String] = []
  if value is Some(Array(items)) {
    for item in items {
      if item is String(text) {
        result.push(text)
      }
    }
  }
  result
}

///|
fn safe_oauth_url(
  value : String,
  context : String,
) -> String raise MCPClientOAuthError {
  let lower = value.to_lower()
  guard (lower.has_prefix("https://") || lower.has_prefix("http://")) &&
    !lower.has_prefix("javascript:") &&
    !lower.has_prefix("data:") &&
    !lower.has_prefix("vbscript:") else {
    raise MCPClientOAuthError(
      message=context + " must be a safe HTTP(S) URL",
      cause=None,
    )
  }
  value
}

///|
/// Decode and validate an OAuth 2.1 token response.
pub fn decode_oauth_tokens(
  value : Json,
) -> OAuthTokens raise MCPClientOAuthError {
  guard value is Object(fields) else {
    raise MCPClientOAuthError(
      message="OAuth token response must be an object",
      cause=None,
    )
  }
  guard fields.get("access_token") is Some(String(access_token)) &&
    fields.get("token_type") is Some(String(token_type)) else {
    raise MCPClientOAuthError(
      message="OAuth token response is missing access_token or token_type",
      cause=None,
    )
  }
  {
    access_token,
    id_token: optional_string(fields, "id_token"),
    token_type,
    expires_in: optional_int(fields, "expires_in"),
    scope: optional_string(fields, "scope"),
    refresh_token: optional_string(fields, "refresh_token"),
    authorization_server: optional_string(fields, "authorization_server"),
    token_endpoint: optional_string(fields, "token_endpoint"),
  }
}

///|
/// AI SDK-style spelling for `decode_oauth_tokens`.
pub fn decodeOAuthTokens(value : Json) -> OAuthTokens raise MCPClientOAuthError {
  decode_oauth_tokens(value)
}

///|
fn oauth_required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise MCPClientOAuthError {
  match fields.get(name) {
    Some(String(value)) => value
    _ =>
      raise MCPClientOAuthError(
        message="OAuth metadata is missing " + name,
        cause=None,
      )
  }
}

///|
fn decode_oauth_metadata(
  value : Json,
) -> OAuthAuthorizationServerMetadata raise MCPClientOAuthError {
  guard value is Object(fields) else {
    raise MCPClientOAuthError(
      message="OAuth metadata must be an object",
      cause=None,
    )
  }
  {
    issuer: safe_oauth_url(
      oauth_required_string(fields, "issuer"),
      "OAuth issuer",
    ),
    authorization_endpoint: safe_oauth_url(
      oauth_required_string(fields, "authorization_endpoint"),
      "OAuth authorization endpoint",
    ),
    token_endpoint: safe_oauth_url(
      oauth_required_string(fields, "token_endpoint"),
      "OAuth token endpoint",
    ),
    registration_endpoint: optional_string(fields, "registration_endpoint"),
    response_types_supported: decode_string_array(
      fields.get("response_types_supported"),
    ),
    grant_types_supported: decode_string_array(
      fields.get("grant_types_supported"),
    ),
    code_challenge_methods_supported: decode_string_array(
      fields.get("code_challenge_methods_supported"),
    ),
    token_endpoint_auth_methods_supported: decode_string_array(
      fields.get("token_endpoint_auth_methods_supported"),
    ),
    raw: value,
  }
}

///|
fn oauth_origin(url : String) -> String? {
  let authority = @provider_utils.url_authority(url)
  authority.map(value => {
    (if url.has_prefix("https://") { "https://" } else { "http://" }) + value
  })
}

///|
fn oauth_path(url : String) -> String {
  match oauth_origin(url) {
    Some(origin) => {
      let suffix = url[origin.length():].to_owned()
      let path = suffix.split("?").to_array()[0]
      let path = path.split("#").to_array()[0]
      if path == "" {
        "/"
      } else {
        path.to_owned()
      }
    }
    None => "/"
  }
}

///|
/// Extract RFC 9728 resource metadata URL from a WWW-Authenticate header.
pub fn extract_resource_metadata_url(header : String) -> String? {
  let lower = header.to_lower()
  guard lower.has_prefix("bearer ") else { return None }
  guard lower.find("resource_metadata=\"") is Some(index) else { return None }
  let start = index + "resource_metadata=\"".length()
  let remainder = header[start:]
  guard remainder.find("\"") is Some(end) else { return None }
  let value = remainder[:end].to_owned()
  Some(safe_oauth_url(value, "resource metadata URL")) catch {
    _ => None
  }
}

///|
/// AI SDK-style spelling for `extract_resource_metadata_url`.
pub fn extractResourceMetadataUrl(header : String) -> String? {
  extract_resource_metadata_url(header)
}

///|
/// Build OAuth and OIDC discovery URLs in MCP priority order.
pub fn build_discovery_urls(authorization_server_url : String) -> Array[String] {
  guard oauth_origin(authorization_server_url) is Some(origin) else {
    return []
  }
  let path = oauth_path(authorization_server_url)
    .strip_suffix("/")
    .unwrap_or(oauth_path(authorization_server_url))
    .to_owned()
  if path == "" || path == "/" {
    [
      origin + "/.well-known/oauth-authorization-server",
      origin + "/.well-known/openid-configuration",
    ]
  } else {
    [
      origin + "/.well-known/oauth-authorization-server" + path,
      origin + "/.well-known/oauth-authorization-server",
      origin + "/.well-known/openid-configuration" + path,
      origin + path + "/.well-known/openid-configuration",
    ]
  }
}

///|
/// AI SDK-style spelling for `build_discovery_urls`.
pub fn buildDiscoveryUrls(authorization_server_url : String) -> Array[String] {
  build_discovery_urls(authorization_server_url)
}

///|
/// Discover and validate OAuth authorization server metadata.
pub async fn discover_authorization_server_metadata(
  authorization_server_url~ : String,
  protocol_version? : String = LATEST_PROTOCOL_VERSION,
  http_transport? : &@provider_utils.HttpTransport,
) -> OAuthAuthorizationServerMetadata? {
  let transport = http_transport.unwrap_or(
    @provider_utils.native_http_transport(),
  )
  for url in build_discovery_urls(authorization_server_url) {
    let response = transport.fetch(
      @provider_utils.HttpRequest::get(url~, headers={
        "MCP-Protocol-Version": protocol_version,
      }),
    ) catch {
      _ => continue
    }
    if !response.is_success() {
      continue
    }
    let value = @json.parse(response.body_text()) catch { _ => continue }
    let metadata = decode_oauth_metadata(value) catch { _ => continue }
    let expected = if url.contains(authorization_server_url) {
      authorization_server_url
      .strip_suffix("/")
      .unwrap_or(authorization_server_url)
      .to_owned()
    } else {
      oauth_origin(authorization_server_url).unwrap_or(authorization_server_url)
    }
    if metadata.issuer.strip_suffix("/").unwrap_or(metadata.issuer).to_owned() ==
      expected {
      return Some(metadata)
    }
  }
  None
}

///|
/// AI SDK-style spelling for `discover_authorization_server_metadata`.
pub async fn discoverAuthorizationServerMetadata(
  authorization_server_url~ : String,
  protocol_version? : String = LATEST_PROTOCOL_VERSION,
  http_transport? : &@provider_utils.HttpTransport,
) -> OAuthAuthorizationServerMetadata? {
  discover_authorization_server_metadata(
    authorization_server_url~,
    protocol_version~,
    http_transport?,
  )
}

///|
fn oauth_unreserved(byte : Byte) -> Bool {
  (byte >= b'a' && byte <= b'z') ||
  (byte >= b'A' && byte <= b'Z') ||
  (byte >= b'0' && byte <= b'9') ||
  byte == b'-' ||
  byte == b'.' ||
  byte == b'_' ||
  byte == b'~'
}

///|
fn oauth_hex(value : Int) -> Char {
  if value < 10 {
    (b'0' + value.to_byte()).to_char()
  } else {
    (b'A' + (value - 10).to_byte()).to_char()
  }
}

///|
fn oauth_encode(value : String) -> String {
  let output = StringBuilder::new()
  for byte in @utf8.encode(value) {
    if oauth_unreserved(byte) {
      output.write_char(byte.to_char())
    } else {
      output.write_char('%')
      output.write_char(oauth_hex(byte.to_int() / 16))
      output.write_char(oauth_hex(byte.to_int() % 16))
    }
  }
  output.to_string()
}

///|
fn append_oauth_query(
  url : String,
  entries : Array[(String, String)],
) -> String {
  let encoded = [
    for entry in entries => oauth_encode(entry.0) + "=" + oauth_encode(entry.1)
  ]
  url + (if url.contains("?") { "&" } else { "?" }) + encoded.join("&")
}

///|
/// Start OAuth authorization using PKCE S256.
pub fn start_authorization(
  authorization_server_url~ : String,
  client_information~ : OAuthClientInformation,
  redirect_url~ : String,
  code_verifier~ : String,
  metadata? : OAuthAuthorizationServerMetadata,
  scope? : String,
  state? : String,
  resource? : String,
) -> OAuthAuthorizationStart raise MCPClientOAuthError {
  guard code_verifier.length() >= 43 && code_verifier.length() <= 128 else {
    raise MCPClientOAuthError(
      message="PKCE code verifier must contain 43 to 128 characters",
      cause=None,
    )
  }
  let endpoint = match metadata {
    Some(value) => {
      guard value.response_types_supported.contains("code") else {
        raise MCPClientOAuthError(
          message="OAuth server does not support response type code",
          cause=None,
        )
      }
      guard value.code_challenge_methods_supported.contains("S256") else {
        raise MCPClientOAuthError(
          message="OAuth server does not support PKCE S256",
          cause=None,
        )
      }
      value.authorization_endpoint
    }
    None =>
      oauth_origin(authorization_server_url).unwrap_or(authorization_server_url) +
      "/authorize"
  }
  let digest = @mooncry.sha256(@utf8.encode(code_verifier))
  let challenge = @base64.encode(digest, padding=false)
    .replace(old="+", new="-")
    .replace(old="/", new="_")
  let entries : Array[(String, String)] = [
    ("response_type", "code"),
    ("client_id", client_information.client_id),
    ("code_challenge", challenge),
    ("code_challenge_method", "S256"),
    ("redirect_uri", redirect_url),
  ]
  if state is Some(value) {
    entries.push(("state", value))
  }
  if scope is Some(value) {
    entries.push(("scope", value))
    if value.split(" ").any(item => item == "offline_access") {
      entries.push(("prompt", "consent"))
    }
  }
  if resource is Some(value) {
    entries.push(
      ("resource", value.strip_suffix("/").unwrap_or(value).to_owned()),
    )
  }
  { authorization_url: append_oauth_query(endpoint, entries), code_verifier }
}

///|
/// AI SDK-style spelling for `start_authorization`.
pub fn startAuthorization(
  authorization_server_url~ : String,
  client_information~ : OAuthClientInformation,
  redirect_url~ : String,
  code_verifier~ : String,
  metadata? : OAuthAuthorizationServerMetadata,
  scope? : String,
  state? : String,
  resource? : String,
) -> OAuthAuthorizationStart raise MCPClientOAuthError {
  start_authorization(
    authorization_server_url~,
    client_information~,
    redirect_url~,
    code_verifier~,
    metadata?,
    scope?,
    state?,
    resource?,
  )
}

///|
/// Parse an OAuth JSON error response.
pub fn parse_oauth_error_response(body : String) -> MCPClientOAuthError {
  let value = @json.parse(body) catch { _ => Json::null() }
  match value {
    Object(fields) => {
      let error = optional_string(fields, "error").unwrap_or("server_error")
      let description = optional_string(fields, "error_description").unwrap_or(
        "",
      )
      let uri = optional_string(fields, "error_uri")
      MCPClientOAuthError(
        message=if description == "" { error } else { description },
        cause=uri,
      )
    }
    _ =>
      MCPClientOAuthError(
        message="Invalid OAuth error response: " + body,
        cause=None,
      )
  }
}

///|
/// Check whether a requested resource is the configured path or a descendant.
pub fn check_resource_allowed(
  requested_resource : String,
  configured_resource : String,
) -> Bool {
  guard oauth_origin(requested_resource) == oauth_origin(configured_resource) else {
    return false
  }
  let requested = oauth_path(requested_resource)
    .strip_suffix("/")
    .unwrap_or(oauth_path(requested_resource))
    .to_owned() +
    "/"
  let configured = oauth_path(configured_resource)
    .strip_suffix("/")
    .unwrap_or(oauth_path(configured_resource))
    .to_owned() +
    "/"
  requested.has_prefix(configured)
}

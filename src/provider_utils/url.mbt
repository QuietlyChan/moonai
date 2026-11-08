///|
/// Remove one trailing slash from a provider endpoint.
pub fn without_trailing_slash(url : String) -> String {
  url.strip_suffix("/").unwrap_or(url).to_owned()
}

///|
/// Remove one trailing slash while preserving an omitted URL, matching AI SDK.
pub fn withoutTrailingSlash(url : String?) -> String? {
  match url {
    Some(value) => Some(without_trailing_slash(value))
    None => None
  }
}

///|
/// Append a path unless the configured endpoint already ends with it.
pub fn append_path(url : String, path : String) -> String {
  let base = without_trailing_slash(url)
  let normalized_path = if path.has_prefix("/") { path } else { "/\{path}" }
  if base.has_suffix(normalized_path) {
    base
  } else {
    "\{base}\{normalized_path}"
  }
}

///|
/// Percent-encode one URL path segment. Standalone dot segments are
/// double-encoded so URL normalization cannot turn provider-owned
/// identifiers into path traversal.
pub fn encode_path_segment(value : String) -> String {
  let encoded = encode_query_component(value)
  if encoded == "." {
    "%252E"
  } else if encoded == ".." {
    "%252E%252E"
  } else {
    encoded
  }
}

///|
fn is_query_unreserved(value : Byte) -> Bool {
  (value >= b'a' && value <= b'z') ||
  (value >= b'A' && value <= b'Z') ||
  (value >= b'0' && value <= b'9') ||
  value == b'-' ||
  value == b'.' ||
  value == b'_' ||
  value == b'~'
}

///|
fn hex_digit(value : Int32) -> Char {
  if value < 10 {
    (b'0' + value.to_byte()).to_char()
  } else {
    (b'A' + (value - 10).to_byte()).to_char()
  }
}

///|
/// Percent-encode one UTF-8 query-string component according to RFC 3986.
fn encode_query_component(value : String) -> String {
  let result = StringBuilder(size_hint=value.length())
  let bytes = @utf8.encode(value)
  for index = 0; index < bytes.length(); index = index + 1 {
    let byte = bytes[index]
    if is_query_unreserved(byte) {
      result.write_object(byte.to_char())
    } else {
      result.write_string("%")
      result.write_object(hex_digit(byte.to_int() / 16))
      result.write_object(hex_digit(byte.to_int() % 16))
    }
  }
  result.to_string()
}

///|
/// Append encoded query parameters to a complete endpoint URL.
pub fn append_query(url : String, query_params : Map[String, String]) -> String {
  if query_params.length() == 0 {
    return url
  }
  let parts : Array[String] = []
  for entry in query_params.iter2() {
    let (key, value) = entry
    parts.push(
      "\{encode_query_component(key)}=\{encode_query_component(value)}",
    )
  }
  let separator = if url.contains("?") { "&" } else { "?" }
  let query = parts.join("&")
  "\{url}\{separator}\{query}"
}

///|
/// Extract the authority component (`host[:port]`) from an absolute URL.
/// User information is rejected so credentials cannot leak into derived
/// provider endpoints.
pub fn url_authority(url : String) -> String? {
  guard url.find("://") is Some(protocol_end) else { return None }
  let remainder = url[protocol_end + 3:]
  let mut authority_end = remainder.length()
  for separator in ["/", "?", "#"] {
    match remainder.find(separator) {
      Some(index) if index < authority_end => authority_end = index
      _ => ()
    }
  }
  let authority = remainder[:authority_end].to_owned()
  if authority == "" || authority.contains("@") {
    None
  } else {
    Some(authority)
  }
}

///|
/// Remove credentials, paths, queries, and fragments from an HTTP endpoint.
/// Invalid or non-HTTP URLs are omitted instead of being returned verbatim.
fn sanitize_http_url_origin(url : String) -> String? {
  guard url.find("://") is Some(protocol_end) else { return None }
  let scheme = url[:protocol_end].to_owned().to_lower()
  guard scheme == "http" || scheme == "https" else { return None }
  let remainder = url[protocol_end + 3:].to_owned()
  let mut end = remainder.length()
  for separator in ["/", "?", "#"] {
    match remainder.find(separator) {
      Some(index) if index < end => end = index
      _ => ()
    }
  }
  let raw_authority = remainder[:end].to_owned()
  let authority = match raw_authority.rev_find("@") {
    Some(index) => raw_authority[index + 1:].to_owned()
    None => raw_authority
  }
  guard authority != "" else { return None }
  for byte in @utf8.encode(authority) {
    let value = byte.to_int()
    guard (value >= 0x30 && value <= 0x39) ||
      (value >= 0x41 && value <= 0x5a) ||
      (value >= 0x61 && value <= 0x7a) ||
      byte == b'.' ||
      byte == b'-' ||
      byte == b':' ||
      byte == b'[' ||
      byte == b']' else {
      return None
    }
  }
  let normalized_authority = authority.to_lower()
  let normalized_authority = if (
      scheme == "https" && normalized_authority.has_suffix(":443")
    ) ||
    (scheme == "http" && normalized_authority.has_suffix(":80")) {
    normalized_authority[:-4].to_owned()
  } else {
    normalized_authority
  }
  Some("\{scheme}://\{normalized_authority}")
}

///|
/// Preserve request diagnostics while stripping sensitive endpoint components.
pub fn sanitize_request_metadata(
  request : @provider.RequestMetadata?,
) -> @provider.RequestMetadata? {
  match request {
    Some(value) =>
      Some(
        @provider.RequestMetadata::new(
          url=sanitize_http_url_origin(value.url).unwrap_or(""),
          headers=copy_headers(value.headers),
          body=value.body,
        ),
      )
    None => None
  }
}

///|
/// Copy headers so provider factories and models do not share mutable maps.
pub fn copy_headers(headers : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    result[key] = value
  }
  result
}

///|
/// Merge HTTP headers with call-level values taking precedence.
pub fn merge_headers(
  base : Map[String, String],
  overrides : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in base.iter2() {
    let (key, value) = entry
    let normalized_key = key.to_lower()
    let mut overridden = false
    for override_entry in overrides.iter2() {
      let (override_key, _) = override_entry
      if override_key.to_lower() == normalized_key {
        overridden = true
        break
      }
    }
    if !overridden {
      result[key] = value
    }
  }
  for entry in overrides.iter2() {
    let (key, value) = entry
    result[key] = value
  }
  result
}

///|
/// Combine ordered header maps with later maps taking precedence.
///
/// This mirrors AI SDK's record-spread `combineHeaders` helper. Use
/// `merge_headers` when case-insensitive override behavior is required.
pub fn combine_headers(
  header_groups : Array[Map[String, String]],
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for headers in header_groups {
    for entry in headers.iter2() {
      let (key, value) = entry
      result[key] = value
    }
  }
  result
}

///|
/// AI SDK-style spelling for `combine_headers`.
pub fn combineHeaders(
  header_groups : Array[Map[String, String]],
) -> Map[String, String] {
  combine_headers(header_groups)
}

///|
/// Normalize header names to lower case without mutating the input map.
pub fn normalize_headers(headers : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    result[key.to_lower()] = value
  }
  result
}

///|
/// AI SDK-style spelling for `normalize_headers`.
pub fn normalizeHeaders(headers : Map[String, String]) -> Map[String, String] {
  normalize_headers(headers)
}

///|
fn is_blocked_request_header(name : String) -> Bool {
  let blocked = [
    "connection", "keep-alive", "te", "trailer", "transfer-encoding", "upgrade",
    "host", "forwarded", "proxy-authorization", "via", "x-forwarded-for", "x-forwarded-host",
    "x-forwarded-proto", "x-real-ip", "metadata", "metadata-flavor", "x-aws-ec2-metadata-token",
    "x-metadata-token", "cookie", "set-cookie",
  ]
  blocked.any(value => value == name)
}

///|
/// Remove routing, proxy, metadata, cookie, and hop-by-hop headers before
/// forwarding a request to an untrusted URL.
pub fn sanitize_request_headers(
  headers : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    if !is_blocked_request_header(key.to_lower()) {
      result[key] = value
    }
  }
  result
}

///|
/// AI SDK-style spelling for `sanitize_request_headers`.
pub fn sanitizeRequestHeaders(
  headers : Map[String, String],
) -> Map[String, String] {
  sanitize_request_headers(headers)
}

///|
/// Append provider identifiers to the User-Agent header without mutating the
/// caller's map. Header lookup is case-insensitive, matching the Fetch Headers
/// behavior used by the TypeScript AI SDK.
pub fn with_user_agent_suffix(
  headers : Map[String, String],
  suffixes : Array[String],
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  let mut current = ""
  for entry in headers.iter2() {
    let (key, value) = entry
    if key.to_lower() == "user-agent" {
      current = value.trim().to_owned()
    } else {
      result[key] = value
    }
  }
  let parts : Array[String] = []
  if current != "" {
    parts.push(current)
  }
  for suffix in suffixes {
    let value = suffix.trim().to_owned()
    if value != "" {
      parts.push(value)
    }
  }
  if parts.length() > 0 {
    result["user-agent"] = parts.join(" ")
  }
  result
}

///|
/// AI SDK-style spelling for `with_user_agent_suffix`.
pub fn withUserAgentSuffix(
  headers : Map[String, String],
  suffixes : Array[String],
) -> Map[String, String] {
  with_user_agent_suffix(headers, suffixes)
}

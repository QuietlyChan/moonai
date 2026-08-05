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

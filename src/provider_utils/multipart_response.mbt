///|
/// One part of a multipart response body: lowercased header names plus the
/// raw body bytes between the header separator and the next boundary.
pub(all) struct MultipartResponsePart {
  headers : Map[String, String]
  body : Bytes
} derive(Debug)

///|
/// Extract the boundary token from a `multipart/*` content-type header.
/// Handles both quoted and unquoted spellings.
pub fn multipart_boundary(content_type : String) -> String? {
  let marker = "boundary="
  let index = match content_type.find(marker) {
    Some(index) => index
    None => return None
  }
  let rest = content_type[index + marker.length():].to_owned()
  let token = if rest.has_prefix("\"") {
    let inner = rest[1:].to_owned()
    match inner.find("\"") {
      Some(end) => inner[:end].to_owned()
      None => inner
    }
  } else {
    match rest.find(";") {
      Some(end) => rest[:end].to_owned()
      None => rest
    }
  }
  let trimmed = token.trim().to_owned()
  if trimmed == "" {
    None
  } else {
    Some(trimmed)
  }
}

///|
fn multipart_is_delimiter_at(data : Bytes, delimiter : Bytes, at : Int) -> Bool {
  guard at + delimiter.length() <= data.length() else { return false }
  for j = 0; j < delimiter.length(); j = j + 1 {
    if data[at + j] != delimiter[j] {
      return false
    }
  }
  true
}

///|
fn multipart_copy(data : Bytes, start : Int, end : Int) -> Bytes {
  let out = @buffer.Buffer()
  for i = start; i < end; i = i + 1 {
    out.write_byte(data[i])
  }
  out.to_bytes()
}

///|
fn multipart_header_text(data : Bytes) -> String {
  @utf8.decode(data) catch {
    _ => ""
  }
}

///|
/// Split a multipart body (delimited by `boundary`, taken from the response
/// content-type) into its parts. Part header names are lowercased. Raises
/// when the content type carries no boundary.
pub fn parse_multipart_response(
  content_type~ : String,
  data~ : Bytes,
) -> Array[MultipartResponsePart] raise {
  let boundary = match multipart_boundary(content_type) {
    Some(token) => token
    None =>
      fail(
        "multipart response missing boundary in content-type: \{content_type}",
      )
  }
  let delimiter = @utf8.encode("--\{boundary}")
  // Locate every delimiter occurrence (`--boundary`).
  let positions : Array[Int] = []
  let mut index = 0
  while index <= data.length() - delimiter.length() {
    if multipart_is_delimiter_at(data, delimiter, index) {
      positions.push(index)
      index = index + delimiter.length()
    } else {
      index = index + 1
    }
  }
  let parts : Array[MultipartResponsePart] = []
  // A delimiter is the final one when the bytes right after it are `--`.
  let is_end_delimiter = position => {
    guard position + delimiter.length() + 2 <= data.length() else {
      return false
    }
    data[position + delimiter.length()] == b'-' &&
    data[position + delimiter.length() + 1] == b'-'
  }
  for i = 0; i < positions.length(); i = i + 1 {
    if is_end_delimiter(positions[i]) {
      break
    }
    guard i + 1 < positions.length() else { break }
    let body_start = positions[i] + delimiter.length()
    // Skip the transport line break right after the delimiter line.
    let mut part_start = body_start
    if part_start + 1 < data.length() &&
      data[part_start] == b'\r' &&
      data[part_start + 1] == b'\n' {
      part_start = part_start + 2
    } else if part_start < data.length() && data[part_start] == b'\n' {
      part_start = part_start + 1
    }
    // Trim the line break preceding the next delimiter.
    let mut part_end = positions[i + 1]
    if part_end - 2 >= part_start &&
      data[part_end - 2] == b'\r' &&
      data[part_end - 1] == b'\n' {
      part_end = part_end - 2
    } else if part_end - 1 >= part_start && data[part_end - 1] == b'\n' {
      part_end = part_end - 1
    }
    guard part_end > part_start else { continue }
    // Find the header/body separator (\r\n\r\n or \n\n).
    let mut header_end = -1
    let mut separator_length = 0
    let mut scan = part_start
    while scan + 1 < part_end {
      if data[scan] == b'\r' &&
        data[scan + 1] == b'\n' &&
        scan + 3 < part_end &&
        data[scan + 2] == b'\r' &&
        data[scan + 3] == b'\n' {
        header_end = scan
        separator_length = 4
        break
      }
      if data[scan] == b'\n' && data[scan + 1] == b'\n' {
        header_end = scan
        separator_length = 2
        break
      }
      scan = scan + 1
    }
    guard header_end >= 0 else { continue }
    let header_text = multipart_header_text(
      multipart_copy(data, part_start, header_end),
    )
    let headers : Map[String, String] = Map([])
    for line in header_text.split("\n") {
      let line = line.trim().to_owned()
      match line.find(":") {
        Some(colon) if colon > 0 => {
          let key = line[:colon].to_owned().trim().to_owned().to_lower()
          let value = line[colon + 1:].to_owned().trim().to_owned()
          headers[key] = value
        }
        _ => ()
      }
    }
    parts.push({
      headers,
      body: multipart_copy(data, header_end + separator_length, part_end),
    })
  }
  parts
}

///|
/// Convenience lookup: the first part whose `content-disposition` carries
/// `name="..."` equal to `name`.
pub fn multipart_response_part_by_name(
  parts : Array[MultipartResponsePart],
  name~ : String,
) -> MultipartResponsePart? {
  for part in parts {
    match part.headers.get("content-disposition") {
      Some(disposition) =>
        if disposition.contains("name=\"\{name}\"") {
          return Some(part)
        }
      None => ()
    }
  }
  None
}

///|
/// Convenience lookup: the first part whose `content-type` starts with
/// `prefix`.
pub fn multipart_response_part_by_content_type_prefix(
  parts : Array[MultipartResponsePart],
  prefix~ : String,
) -> MultipartResponsePart? {
  for part in parts {
    match part.headers.get("content-type") {
      Some(media_type) => if media_type.has_prefix(prefix) { return Some(part) }
      None => ()
    }
  }
  None
}

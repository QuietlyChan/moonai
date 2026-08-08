///|
/// A URL-backed download failed before the asset could be materialized.
///
/// This is intentionally separate from `APICallError`: download URLs often
/// come from model output rather than from a provider endpoint, and callers
/// need to distinguish an unsafe redirect or malformed URL from an API error.
pub(all) suberror DownloadError {
  DownloadError(
    url~ : String,
    message~ : String,
    status_code~ : Int?,
    status_text~ : String?
  )
} derive(Debug, Eq)

///|
/// Default maximum download size used by AI SDK's shared downloader.
pub const DEFAULT_MAX_DOWNLOAD_SIZE : Int64 = 2147483648L

///|
fn download_error(url : String, message : String) -> DownloadError {
  DownloadError(url~, message~, status_code=None, status_text=None)
}

///|
fn percent_decode_data_url(
  url : String,
  value : String,
) -> Bytes raise DownloadError {
  let input = @utf8.encode(value)
  let output = @buffer.Buffer()
  let mut index = 0
  while index < input.length() {
    if input[index] == b'%' {
      guard index + 2 < input.length() else {
        raise download_error(url, "Invalid percent-encoding in data URL")
      }
      let high = match ascii_digit(input[index + 1], 16) {
        Some(value) => value
        None =>
          raise download_error(url, "Invalid percent-encoding in data URL")
      }
      let low = match ascii_digit(input[index + 2], 16) {
        Some(value) => value
        None =>
          raise download_error(url, "Invalid percent-encoding in data URL")
      }
      output.write_byte((high * 16 + low).to_byte())
      index = index + 3
    } else {
      output.write_byte(input[index])
      index = index + 1
    }
  }
  output.to_bytes()
}

///|
fn decode_data_url(url : String) -> (Bytes, String) raise DownloadError {
  guard url.length() >= 5 && url[:5].to_owned().to_lower() == "data:" else {
    raise download_error(url, "Invalid data URL")
  }
  let comma = match url.find(",") {
    Some(value) => value
    None => raise download_error(url, "Data URL is missing a comma separator")
  }
  let metadata = url[5:comma].to_owned()
  let encoded = url[comma + 1:].to_owned()
  let segments = metadata.split(";").to_array()
  let media_type = if segments.length() > 0 && segments[0].contains("/") {
    segments[0].trim().to_owned().to_lower()
  } else {
    "text/plain"
  }
  let mut base64_encoded = false
  for segment in segments {
    if segment.trim().to_owned().to_lower() == "base64" {
      base64_encoded = true
      break
    }
  }
  let decoded = percent_decode_data_url(url, encoded)
  if base64_encoded {
    let base64_value = @utf8.decode(decoded) catch {
      _ => raise download_error(url, "Data URL has a non-ASCII Base64 payload")
    }
    let data = @base64.decode(base64_value) catch {
      _ => raise download_error(url, "Data URL has an invalid Base64 payload")
    }
    (data, media_type)
  } else {
    (decoded, media_type)
  }
}

///|
fn ensure_download_size(
  url : String,
  data : Bytes,
  max_bytes : Int64,
  content_length : Int64?,
) -> Unit raise DownloadError {
  match content_length {
    Some(length) if length > max_bytes =>
      raise download_error(
        url,
        "Download of \{url} exceeded maximum size of \{max_bytes} bytes (Content-Length: \{length}).",
      )
    _ => ()
  }
  guard data.length().to_int64() <= max_bytes else {
    raise download_error(
      url,
      "Download of \{url} exceeded maximum size of \{max_bytes} bytes.",
    )
  }
}

///|
fn ascii_digit(byte : Byte, base : Int) -> Int? {
  let value = byte.to_int()
  let digit = if value >= b'0'.to_int() && value <= b'9'.to_int() {
    value - b'0'.to_int()
  } else if value >= b'a'.to_int() && value <= b'f'.to_int() {
    value - b'a'.to_int() + 10
  } else if value >= b'A'.to_int() && value <= b'F'.to_int() {
    value - b'A'.to_int() + 10
  } else {
    return None
  }
  if digit < base {
    Some(digit)
  } else {
    None
  }
}

///|
fn parse_unsigned(value : String, base : Int) -> Int? {
  let bytes = @utf8.encode(value)
  guard bytes.length() > 0 else { return None }
  let mut result = 0
  for byte in bytes {
    let digit = match ascii_digit(byte, base) {
      Some(value) => value
      None => return None
    }
    result = result * base + digit
  }
  Some(result)
}

///|
fn parse_unsigned_int64(value : String, base : Int) -> Int64? {
  guard value != "" else { return None }
  try @string.parse_int64(value, base~) catch {
    _ => None
  } noraise {
    parsed if parsed >= 0L => Some(parsed)
    _ => None
  }
}

///|
/// Parse the legacy IPv4 spellings accepted by URL parsers, including
/// decimal, hexadecimal, octal, and shortened integer forms.
fn parse_ipv4(value : String) -> Array[Int]? {
  let parts = value.split(".").to_array()
  guard parts.length() >= 1 && parts.length() <= 4 else { return None }
  let numbers : Array[Int64] = []
  for part_view in parts {
    let part = part_view.to_owned()
    guard part != "" else { return None }
    let (digits, base) = if part.has_prefix("0x") || part.has_prefix("0X") {
      (part[2:].to_owned(), 16)
    } else if part.length() > 1 && part.has_prefix("0") {
      (part[1:].to_owned(), 8)
    } else {
      (part, 10)
    }
    let number = match parse_unsigned_int64(digits, base) {
      Some(value) => value
      None => return None
    }
    numbers.push(number)
  }
  let result : Array[Int] = []
  match numbers.length() {
    1 => {
      let value = numbers[0]
      guard value <= 0xffffffffL else { return None }
      result.push((value / 0x1000000L).to_int())
      result.push((value / 0x10000L % 0x100L).to_int())
      result.push((value / 0x100L % 0x100L).to_int())
      result.push((value % 0x100L).to_int())
    }
    2 => {
      guard numbers[0] <= 0xffL && numbers[1] <= 0xffffffL else { return None }
      result.push(numbers[0].to_int())
      result.push((numbers[1] / 0x10000L).to_int())
      result.push((numbers[1] / 0x100L % 0x100L).to_int())
      result.push((numbers[1] % 0x100L).to_int())
    }
    3 => {
      guard numbers[0] <= 0xffL && numbers[1] <= 0xffL && numbers[2] <= 0xffffL else {
        return None
      }
      result.push(numbers[0].to_int())
      result.push(numbers[1].to_int())
      result.push((numbers[2] / 0x100L).to_int())
      result.push((numbers[2] % 0x100L).to_int())
    }
    4 =>
      for number in numbers {
        guard number <= 0xffL else { return None }
        result.push(number.to_int())
      }
    _ => return None
  }
  Some(result)
}

///|
fn is_private_ipv4(value : Array[Int]) -> Bool {
  guard value.length() == 4 else { return true }
  let a = value[0]
  let b = value[1]
  let c = value[2]
  a == 0 ||
  a == 10 ||
  (a == 100 && b >= 64 && b <= 127) ||
  a == 127 ||
  (a == 169 && b == 254) ||
  (a == 172 && b >= 16 && b <= 31) ||
  (a == 192 && b == 0 && c == 0) ||
  (a == 192 && b == 0 && c == 2) ||
  (a == 192 && b == 168) ||
  (a == 198 && (b == 18 || b == 19)) ||
  (a == 198 && b == 51 && c == 100) ||
  (a == 203 && b == 0 && c == 113) ||
  a >= 224
}

///|
fn parse_ipv6_groups(value : String) -> Array[Int]? {
  let address = value.to_lower()
  let zone_stripped = match address.find("%") {
    Some(index) => address[:index].to_owned()
    None => address
  }
  let halves = zone_stripped.split("::").to_array()
  guard halves.length() <= 2 else { return None }
  let parse_half = fn(segment : StringView) -> Array[Int]? {
    if segment.length() == 0 {
      return Some([])
    }
    let parts = segment.split(":").to_array()
    let groups : Array[Int] = []
    for index, part_view in parts {
      let part = part_view.to_owned()
      if part.contains(".") {
        guard index == parts.length() - 1 else { return None }
        let ipv4 = match parse_ipv4(part) {
          Some(value) => value
          None => return None
        }
        groups.push(ipv4[0] * 0x100 + ipv4[1])
        groups.push(ipv4[2] * 0x100 + ipv4[3])
      } else {
        guard part.length() >= 1 && part.length() <= 4 else { return None }
        let group = match parse_unsigned(part, 16) {
          Some(value) => value
          None => return None
        }
        groups.push(group)
      }
    }
    Some(groups)
  }
  let head = match parse_half(halves[0]) {
    Some(value) => value
    None => return None
  }
  if halves.length() == 2 {
    let tail = match parse_half(halves[1]) {
      Some(value) => value
      None => return None
    }
    let fill = 8 - head.length() - tail.length()
    guard fill >= 0 else { return None }
    let result : Array[Int] = []
    for group in head {
      result.push(group)
    }
    for _ in 0..<fill {
      result.push(0)
    }
    for group in tail {
      result.push(group)
    }
    Some(result)
  } else if head.length() == 8 {
    Some(head)
  } else {
    None
  }
}

///|
fn top_zero(groups : Array[Int], count : Int) -> Bool {
  for index in 0..<count {
    if groups[index] != 0 {
      return false
    }
  }
  true
}

///|
fn is_private_ipv6(value : String) -> Bool {
  let groups = match parse_ipv6_groups(value) {
    Some(value) => value
    None => return true
  }
  if top_zero(groups, 7) && (groups[7] == 0 || groups[7] == 1) {
    return true
  }
  if (groups[0] & 0xfe00) == 0xfc00 ||
    (groups[0] & 0xffc0) == 0xfe80 ||
    (groups[0] & 0xffc0) == 0xfec0 ||
    (groups[0] & 0xff00) == 0xff00 ||
    (groups[0] == 0x2001 && groups[1] == 0x0db8) ||
    (groups[0] == 0x3fff && (groups[1] & 0xf000) == 0) {
    return true
  }
  let embeds_ipv4 = top_zero(groups, 6) ||
    (top_zero(groups, 5) && groups[5] == 0xffff) ||
    (top_zero(groups, 4) && groups[4] == 0xffff && groups[5] == 0) ||
    (
      groups[0] == 0x0064 &&
      groups[1] == 0xff9b &&
      groups[2] == 0 &&
      groups[3] == 0 &&
      groups[4] == 0 &&
      groups[5] == 0
    ) ||
    (groups[0] == 0x0064 && groups[1] == 0xff9b && groups[2] == 1)
  if embeds_ipv4 {
    let embedded = [
      groups[6] / 0x100,
      groups[6] % 0x100,
      groups[7] / 0x100,
      groups[7] % 0x100,
    ]
    return is_private_ipv4(embedded)
  }
  false
}

///|
fn authority_end(value : String) -> Int {
  let mut end = value.length()
  for separator in ["/", "?", "#"] {
    match value.find(separator) {
      Some(index) if index < end => end = index
      _ => ()
    }
  }
  end
}

///|
fn valid_download_port(value : String) -> Bool {
  match parse_unsigned(value, 10) {
    Some(port) => port >= 0 && port <= 65535
    None => false
  }
}

///|
fn contains_url_control(value : String) -> Bool {
  for byte in @utf8.encode(value) {
    if byte.to_int() <= 0x20 || byte.to_int() == 0x7f {
      return true
    }
  }
  false
}

///|
/// Extract the host and whether it is an IPv6 literal from an absolute URL.
fn download_url_host(url : String) -> (String, Bool)? {
  guard url.find("://") is Some(scheme_end) else { return None }
  let remainder = url[scheme_end + 3:].to_owned()
  let authority = remainder[:authority_end(remainder)].to_owned()
  guard authority != "" && !authority.contains("@") else { return None }
  if authority.has_prefix("[") {
    guard authority.find("]") is Some(close) else { return None }
    let host = authority[1:close].to_owned()
    let suffix = authority[close + 1:].to_owned()
    guard suffix == "" ||
      (suffix.has_prefix(":") && valid_download_port(suffix[1:].to_owned())) else {
      return None
    }
    Some((host, true))
  } else {
    let colon = authority.find(":")
    match colon {
      Some(index) => {
        let host = authority[:index].to_owned()
        let port = authority[index + 1:].to_owned()
        guard host != "" && valid_download_port(port) else { return None }
        guard !host.contains(":") else { return None }
        Some((host, false))
      }
      None => Some((authority, false))
    }
  }
}

///|
/// Validate that a URL is safe to fetch as an untrusted download.
///
/// This performs literal host checks. The default native downloader also
/// validates and pins the selected DNS result at connect time. An injected
/// transport is responsible for applying an equivalent resolved-address policy.
pub fn validate_download_url(url : String) -> Unit raise DownloadError {
  if url.length() >= 5 && url[:5].to_owned().to_lower() == "data:" {
    return
  }
  guard url.find("://") is Some(scheme_end) else {
    raise download_error(url, "Invalid URL: {url}")
  }
  let scheme = url[:scheme_end].to_owned().to_lower()
  guard scheme == "http" || scheme == "https" else {
    raise download_error(
      url, "URL scheme must be http, https, or data, got {scheme}:",
    )
  }
  guard !contains_url_control(url) else {
    raise download_error(
      url, "URL must not contain spaces or control characters",
    )
  }
  let (host, ipv6) = match download_url_host(url) {
    Some(value) => value
    None => raise download_error(url, "URL must have a valid hostname")
  }
  let normalized_host = host.to_lower()
  let mut hostname = normalized_host
  while hostname.has_suffix(".") {
    hostname = hostname.strip_suffix(".").unwrap_or(hostname).to_owned()
  }
  guard hostname != "" else {
    raise download_error(url, "URL must have a hostname")
  }
  guard !contains_url_control(hostname) else {
    raise download_error(url, "URL must have a valid hostname")
  }
  guard hostname != "localhost" &&
    !hostname.has_suffix(".local") &&
    !hostname.has_suffix(".localhost") else {
    raise download_error(url, "URL with hostname {hostname} is not allowed")
  }
  if ipv6 {
    guard !is_private_ipv6(hostname) else {
      raise download_error(
        url, "URL with IPv6 address [{hostname}] is not allowed",
      )
    }
  } else if parse_ipv4(hostname) is Some(address) {
    guard !is_private_ipv4(address) else {
      raise download_error(url, "URL with IP address {hostname} is not allowed")
    }
  }
}

///|
/// AI SDK-style camel-case spelling.
pub fn validateDownloadURL(url : String) -> Unit raise DownloadError {
  validate_download_url(url)
}

///|
fn download_response_header(
  headers : Map[String, String],
  name : String,
) -> String? {
  let normalized = name.to_lower()
  for entry in headers.iter2() {
    let (key, value) = entry
    if key.to_lower() == normalized {
      return Some(value)
    }
  }
  None
}

///|
/// Read one buffered response while enforcing the shared response-size limit.
///
/// `HttpTransport::fetch` currently returns a fully buffered body, so this
/// boundary cannot stop allocation mid-stream. It still rejects oversized
/// `Content-Length` values and prevents oversized bodies from reaching JSON or
/// provider decoders. Streaming transports enforce their own incremental
/// lifecycle instead.
pub fn read_response_with_size_limit(
  response : HttpResponse,
  url~ : String,
  max_bytes? : Int64 = DEFAULT_MAX_DOWNLOAD_SIZE,
) -> Bytes raise DownloadError {
  let content_length = match
    download_response_header(response.headers, "content-length") {
    Some(value) => parse_unsigned_int64(value.trim().to_owned(), 10)
    None => None
  }
  ensure_download_size(url, response.body, max_bytes, content_length)
  response.body
}

///|
/// AI SDK-style camel-case spelling.
pub fn readResponseWithSizeLimit(
  response : HttpResponse,
  url~ : String,
  max_bytes? : Int64 = DEFAULT_MAX_DOWNLOAD_SIZE,
) -> Bytes raise DownloadError {
  read_response_with_size_limit(response, url~, max_bytes~)
}

///|
fn is_download_redirect_status(status_code : Int) -> Bool {
  status_code == 301 ||
  status_code == 302 ||
  status_code == 303 ||
  status_code == 307 ||
  status_code == 308
}

///|
fn download_url_parts(url : String) -> (String, String, String)? {
  guard url.find("://") is Some(scheme_end) else { return None }
  let scheme = url[:scheme_end].to_owned().to_lower()
  let remainder = url[scheme_end + 3:].to_owned()
  let end = authority_end(remainder)
  let authority = remainder[:end].to_owned()
  guard authority != "" else { return None }
  let path = if end < remainder.length() {
    remainder[end:].to_owned()
  } else {
    "/"
  }
  Some((scheme, authority, path))
}

///|
fn download_same_origin(left : String, right : String) -> Bool {
  match (download_url_parts(left), download_url_parts(right)) {
    (
      Some((left_scheme, left_authority, _)),
      Some((right_scheme, right_authority, _)),
    ) => {
      let normalize_authority = fn(
        scheme : String,
        authority : String,
      ) -> String {
        let normalized = authority.to_lower()
        if (scheme == "https" && normalized.has_suffix(":443")) ||
          (scheme == "http" && normalized.has_suffix(":80")) {
          normalized[:-4].to_owned()
        } else {
          normalized
        }
      }
      left_scheme == right_scheme &&
      normalize_authority(left_scheme, left_authority) ==
      normalize_authority(right_scheme, right_authority)
    }
    _ => false
  }
}

///|
fn has_explicit_url_scheme(value : String) -> Bool {
  let bytes = @utf8.encode(value)
  guard bytes.length() > 0 else { return false }
  let first = bytes[0].to_int()
  guard (first >= b'a'.to_int() && first <= b'z'.to_int()) ||
    (first >= b'A'.to_int() && first <= b'Z'.to_int()) else {
    return false
  }
  for index in 1..<bytes.length() {
    let byte = bytes[index].to_int()
    if byte == b':'.to_int() {
      return true
    }
    let allowed = (byte >= b'a'.to_int() && byte <= b'z'.to_int()) ||
      (byte >= b'A'.to_int() && byte <= b'Z'.to_int()) ||
      (byte >= b'0'.to_int() && byte <= b'9'.to_int()) ||
      byte == b'+'.to_int() ||
      byte == b'-'.to_int() ||
      byte == b'.'.to_int()
    if !allowed {
      return false
    }
  }
  false
}

///|
/// Resolve a redirect target using the same-origin URL rules needed by HTTP
/// downloads. The returned value is validated separately before it is sent.
fn resolve_download_redirect(
  current : String,
  location : String,
) -> String raise DownloadError {
  let target = location.trim().to_owned()
  guard target != "" else {
    raise download_error(current, "Redirect location is empty")
  }
  if has_explicit_url_scheme(target) {
    return target
  }
  let (scheme, authority, current_path) = match download_url_parts(current) {
    Some(value) => value
    None =>
      raise download_error(current, "Cannot resolve redirect from invalid URL")
  }
  if target.has_prefix("//") {
    return "\{scheme}:\{target}"
  }

  let split_suffix = fn(path : String) -> (String, String) {
    let mut end = path.length()
    for separator in ["?", "#"] {
      match path.find(separator) {
        Some(index) if index < end => end = index
        _ => ()
      }
    }
    (path[:end].to_owned(), path[end:].to_owned())
  }
  let (current_path_only, _) = split_suffix(current_path)
  let (target_path, target_suffix) = split_suffix(target)
  let combined = if target_path.has_prefix("/") {
    target_path
  } else if target_path == "" {
    current_path_only
  } else {
    let directory_end = current_path_only.rev_find("/").unwrap_or(0) + 1
    "\{current_path_only[:directory_end]}\{target_path}"
  }
  let segments = combined.split("/").to_array()
  let normalized : Array[String] = []
  for segment_view in segments {
    let segment = segment_view.to_owned()
    if segment == "" || segment == "." {
      continue
    }
    if segment == ".." {
      if normalized.length() > 0 {
        normalized.pop() |> ignore
      }
    } else {
      normalized.push(segment)
    }
  }
  let normalized_path = "/" + normalized.join("/")
  let trailing_slash = combined.has_suffix("/") ||
    target_path == "." ||
    target_path == ".."
  let path = if trailing_slash && !normalized_path.has_suffix("/") {
    normalized_path + "/"
  } else {
    normalized_path
  }
  "\{scheme}://\{authority}\{path}\{target_suffix}"
}

///|
fn download_redirect_headers(
  headers : Map[String, String],
  current_url : String,
  next_url : String,
) -> Map[String, String] {
  if download_same_origin(current_url, next_url) {
    return copy_headers(headers)
  }
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    if key.to_lower() == "user-agent" {
      result[key] = value
    }
  }
  result
}

///|
fn sanitize_download_headers(
  headers : Map[String, String],
) -> Map[String, String] {
  sanitize_request_headers(headers)
}

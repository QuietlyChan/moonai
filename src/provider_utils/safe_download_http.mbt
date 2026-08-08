///|
/// Maximum aggregate size of one HTTP response header block.
const SAFE_DOWNLOAD_MAX_HEADER_BYTES : Int = 65_536

///|
/// Maximum size used for individual status, header, and chunk-size lines.
const SAFE_DOWNLOAD_MAX_LINE_BYTES : Int = 8_192

///|
priv struct SafeDownloadTarget {
  scheme : String
  hostname : String
  port : Int
  authority : String
  request_target : String
}

///|
priv enum SafeDownloadSocket {
  SafeDownloadPlain(@socket.Tcp)
  SafeDownloadTls(@socket.Tcp, @tls.Tls)
}

///|
async fn SafeDownloadSocket::write(
  self : SafeDownloadSocket,
  data : Bytes,
) -> Unit {
  match self {
    SafeDownloadPlain(tcp) => tcp.write(data)
    SafeDownloadTls(_, tls) => tls.write(data)
  }
}

///|
async fn SafeDownloadSocket::read_some(
  self : SafeDownloadSocket,
  max_len : Int,
) -> Bytes? {
  match self {
    SafeDownloadPlain(tcp) => tcp.read_some(max_len~)
    SafeDownloadTls(_, tls) => tls.read_some(max_len~)
  }
}

///|
fn SafeDownloadSocket::close(self : SafeDownloadSocket) -> Unit {
  match self {
    SafeDownloadPlain(tcp) => tcp.close()
    SafeDownloadTls(tcp, tls) => {
      tls.close()
      tcp.close()
    }
  }
}

///|
priv struct SafeDownloadConnection {
  socket : SafeDownloadSocket
  mut buffered : Bytes
  mut offset : Int
}

///|
fn SafeDownloadConnection::available(self : SafeDownloadConnection) -> Int {
  self.buffered.length() - self.offset
}

///|
async fn SafeDownloadConnection::read_more(
  self : SafeDownloadConnection,
  max_len : Int,
) -> Bool {
  match self.socket.read_some(max_len) {
    None => false
    Some(data) => {
      self.buffered = if self.offset < self.buffered.length() {
        self.buffered[self.offset:].to_owned() + data
      } else {
        data
      }
      self.offset = 0
      true
    }
  }
}

///|
async fn SafeDownloadConnection::read_line(
  self : SafeDownloadConnection,
  url : String,
  max_bytes : Int,
) -> String {
  for ;; {
    let remaining = self.buffered[self.offset:].to_owned()
    match remaining.find(b"\r\n") {
      Some(index) => {
        guard index <= max_bytes else {
          raise download_error(
            url, "HTTP response line exceeded the size limit",
          )
        }
        let line = @utf8.decode(remaining[:index]) catch {
          _ =>
            raise download_error(
              url, "HTTP response header contains invalid UTF-8",
            )
        }
        self.offset = self.offset + index + 2
        return line
      }
      None => {
        guard remaining.length() <= max_bytes else {
          raise download_error(
            url, "HTTP response line exceeded the size limit",
          )
        }
        let request_size = @cmp.minimum(
          8_192,
          max_bytes + 2 - remaining.length(),
        )
        guard request_size > 0 && self.read_more(request_size) else {
          raise download_error(
            url, "HTTP response ended before a complete line",
          )
        }
      }
    }
  }
}

///|
async fn SafeDownloadConnection::read_exactly(
  self : SafeDownloadConnection,
  url : String,
  length : Int,
) -> Bytes {
  let output = @buffer.Buffer(size_hint=length)
  let mut remaining = length
  while remaining > 0 {
    let available = self.available()
    if available == 0 {
      guard self.read_more(@cmp.minimum(65_536, remaining)) else {
        raise download_error(url, "HTTP response body ended unexpectedly")
      }
      continue
    }
    let count = @cmp.minimum(available, remaining)
    output.write_bytes(self.buffered[self.offset:self.offset + count])
    self.offset = self.offset + count
    remaining = remaining - count
  }
  output.to_bytes()
}

///|
fn write_safe_download_body_chunk(
  output : @buffer.Buffer,
  data : BytesView,
  url : String,
  max_bytes : Int64,
) -> Unit raise DownloadError {
  let next_length = output.length().to_int64() + data.length().to_int64()
  guard next_length <= max_bytes else {
    raise download_error(
      url,
      "Download of \{url} exceeded maximum size of \{max_bytes} bytes.",
    )
  }
  output.write_bytes(data)
}

///|
async fn SafeDownloadConnection::read_to_end(
  self : SafeDownloadConnection,
  url : String,
  max_bytes : Int64,
) -> Bytes {
  let output = @buffer.Buffer()
  if self.available() > 0 {
    write_safe_download_body_chunk(
      output,
      self.buffered[self.offset:],
      url,
      max_bytes,
    )
    self.offset = self.buffered.length()
  }
  for ;; {
    match self.socket.read_some(65_536) {
      None => break
      Some(data) =>
        write_safe_download_body_chunk(output, data[:], url, max_bytes)
    }
  }
  output.to_bytes()
}

///|
async fn SafeDownloadConnection::read_chunked_body(
  self : SafeDownloadConnection,
  url : String,
  max_bytes : Int64,
) -> Bytes {
  let output = @buffer.Buffer()
  for ;; {
    let line = self.read_line(url, SAFE_DOWNLOAD_MAX_LINE_BYTES)
    let size_text = (match line.find(";") {
        Some(index) => line[:index].to_owned()
        None => line
      })
      .trim()
      .to_owned()
    let chunk_size = match parse_unsigned_int64(size_text, 16) {
      Some(value) => value
      None =>
        raise download_error(url, "HTTP response has an invalid chunk size")
    }
    if chunk_size == 0L {
      let mut trailer_bytes = 0
      for ;; {
        let trailer = self.read_line(url, SAFE_DOWNLOAD_MAX_LINE_BYTES)
        trailer_bytes = trailer_bytes + trailer.length() + 2
        guard trailer_bytes <= SAFE_DOWNLOAD_MAX_HEADER_BYTES else {
          raise download_error(
            url, "HTTP response trailers exceeded the size limit",
          )
        }
        if trailer == "" {
          break
        }
      }
      break
    }
    guard chunk_size <= max_bytes - output.length().to_int64() &&
      chunk_size <= 0x7fffffffL else {
      raise download_error(
        url,
        "Download of \{url} exceeded maximum size of \{max_bytes} bytes.",
      )
    }
    let chunk = self.read_exactly(url, chunk_size.to_int())
    write_safe_download_body_chunk(output, chunk[:], url, max_bytes)
    guard self.read_exactly(url, 2) == b"\r\n" else {
      raise download_error(url, "HTTP response chunk is missing its terminator")
    }
  }
  output.to_bytes()
}

///|
fn safe_download_target(url : String) -> SafeDownloadTarget raise DownloadError {
  validate_download_url(url)
  let (scheme, authority, path) = match download_url_parts(url) {
    Some(parts) => parts
    None => raise download_error(url, "URL must be an absolute HTTP URL")
  }
  let (raw_hostname, is_ipv6) = match download_url_host(url) {
    Some(parts) => parts
    None => raise download_error(url, "URL must have a valid hostname")
  }
  let mut hostname = raw_hostname
  while hostname.has_suffix(".") {
    hostname = hostname.strip_suffix(".").unwrap_or(hostname).to_owned()
  }
  let port = if is_ipv6 {
    let close = authority.find("]").unwrap_or(authority.length())
    let suffix = authority[close + 1:].to_owned()
    if suffix.has_prefix(":") {
      parse_unsigned(suffix[1:].to_owned(), 10).unwrap_or(
        if scheme == "https" {
          443
        } else {
          80
        },
      )
    } else if scheme == "https" {
      443
    } else {
      80
    }
  } else {
    match authority.find(":") {
      Some(index) =>
        parse_unsigned(authority[index + 1:].to_owned(), 10).unwrap_or(
          if scheme == "https" {
            443
          } else {
            80
          },
        )
      None => if scheme == "https" { 443 } else { 80 }
    }
  }
  let without_fragment = match path.find("#") {
    Some(index) => path[:index].to_owned()
    None => path
  }
  let request_target = if without_fragment == "" {
    "/"
  } else if without_fragment.has_prefix("?") {
    "/" + without_fragment
  } else {
    without_fragment
  }
  { scheme, hostname, port, authority, request_target }
}

///|
fn safe_download_ipv4_text(address : @socket.Addr) -> (String, Array[Int]) {
  let ip = address.ip()
  let parts = [
    ((ip >> 24) & 255).reinterpret_as_int(),
    ((ip >> 16) & 255).reinterpret_as_int(),
    ((ip >> 8) & 255).reinterpret_as_int(),
    (ip & 255).reinterpret_as_int(),
  ]
  ("\{parts[0]}.\{parts[1]}.\{parts[2]}.\{parts[3]}", parts)
}

///|
fn safe_download_ipv6_text(address : @socket.Addr) -> String {
  let rendered = address.to_string()
  match rendered.find("]") {
    Some(close) if rendered.has_prefix("[") => rendered[1:close].to_owned()
    _ => rendered
  }
}

///|
/// Validate the exact address that will be passed to `Tcp::connect`.
fn validate_resolved_download_address(
  hostname : String,
  address : @socket.Addr,
) -> Unit raise DownloadError {
  let (address_text, disallowed) = if address.is_ipv6() {
    let text = safe_download_ipv6_text(address)
    (text, is_private_ipv6(text))
  } else {
    let (text, parts) = safe_download_ipv4_text(address)
    (text, is_private_ipv4(parts))
  }
  guard !disallowed else {
    raise download_error(
      hostname,
      "Hostname \{hostname} resolved to disallowed IP address \{address_text}",
    )
  }
}

///|
fn safe_download_header_name(name : String) -> Bool {
  guard name != "" else { return false }
  for byte in @utf8.encode(name) {
    let value = byte.to_int()
    let allowed = (value >= b'a'.to_int() && value <= b'z'.to_int()) ||
      (value >= b'A'.to_int() && value <= b'Z'.to_int()) ||
      (value >= b'0'.to_int() && value <= b'9'.to_int()) ||
      value == 33 ||
      value == 35 ||
      value == 36 ||
      value == 37 ||
      value == 38 ||
      value == 39 ||
      value == 42 ||
      value == 43 ||
      value == 45 ||
      value == 46 ||
      value == 94 ||
      value == 95 ||
      value == 96 ||
      value == 124 ||
      value == 126
    if !allowed {
      return false
    }
  }
  true
}

///|
fn safe_download_header_value(value : String) -> Bool {
  for byte in @utf8.encode(value) {
    let code = byte.to_int()
    if (code < 0x20 && code != 0x09) || code == 0x7f {
      return false
    }
  }
  true
}

///|
fn safe_download_request_text(
  request : HttpRequest,
  target : SafeDownloadTarget,
) -> String raise DownloadError {
  guard request.meth == HttpGet else {
    raise download_error(
      request.url,
      "Safe download transport only supports GET",
    )
  }
  let output = StringBuilder::new()
  output.write_string("GET \{target.request_target} HTTP/1.1\r\n")
  output.write_string("Host: \{target.authority}\r\n")
  for entry in sanitize_download_headers(request.headers).iter2() {
    let (name, value) = entry
    let normalized = name.to_lower()
    if normalized == "accept-encoding" {
      continue
    }
    guard safe_download_header_name(name) && safe_download_header_value(value) else {
      raise download_error(
        request.url,
        "Download request contains an invalid header",
      )
    }
    output.write_string("\{name}: \{value}\r\n")
  }
  output.write_string("Accept-Encoding: identity\r\n")
  output.write_string("Connection: close\r\n\r\n")
  output.to_string()
}

///|
fn safe_download_status_line(
  line : String,
  url : String,
) -> (Int, String) raise DownloadError {
  guard line.find(" ") is Some(protocol_end) else {
    raise download_error(url, "HTTP response has an invalid status line")
  }
  let protocol = line[:protocol_end]
  guard protocol == "HTTP/1.1" || protocol == "HTTP/1.0" else {
    raise download_error(url, "HTTP response uses an unsupported protocol")
  }
  let rest = line[protocol_end + 1:].to_owned()
  let (code_text, reason) = match rest.find(" ") {
    Some(code_end) =>
      (rest[:code_end].to_owned(), rest[code_end + 1:].to_owned())
    None => (rest, "")
  }
  guard code_text.length() == 3 else {
    raise download_error(url, "HTTP response has an invalid status code")
  }
  let code = @string.parse_int(code_text) catch {
    _ => raise download_error(url, "HTTP response has an invalid status code")
  }
  guard code >= 100 && code <= 599 else {
    raise download_error(url, "HTTP response has an invalid status code")
  }
  (code, reason)
}

///|
async fn SafeDownloadConnection::read_headers(
  self : SafeDownloadConnection,
  url : String,
) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  let mut header_bytes = 0
  for ;; {
    let line = self.read_line(url, SAFE_DOWNLOAD_MAX_LINE_BYTES)
    header_bytes = header_bytes + line.length() + 2
    guard header_bytes <= SAFE_DOWNLOAD_MAX_HEADER_BYTES else {
      raise download_error(url, "HTTP response headers exceeded the size limit")
    }
    if line == "" {
      break
    }
    guard line.find(":") is Some(colon) && colon > 0 else {
      raise download_error(url, "HTTP response contains an invalid header")
    }
    let name = line[:colon].to_owned().to_lower()
    let value = line[colon + 1:].trim().to_owned()
    guard safe_download_header_name(name) && safe_download_header_value(value) else {
      raise download_error(url, "HTTP response contains an invalid header")
    }
    match headers.get(name) {
      Some(previous) if name == "content-length" && previous != value =>
        raise download_error(
          url, "HTTP response has conflicting Content-Length headers",
        )
      Some(_) if name == "content-length" => ()
      Some(previous) => headers[name] = "\{previous},\{value}"
      None => headers[name] = value
    }
  }
  headers
}

///|
async fn SafeDownloadConnection::read_response_body(
  self : SafeDownloadConnection,
  url : String,
  status_code : Int,
  headers : Map[String, String],
  max_bytes : Int64,
) -> Bytes {
  if status_code < 200 ||
    status_code == 204 ||
    status_code == 205 ||
    status_code == 304 ||
    is_download_redirect_status(status_code) {
    return b""
  }
  let transfer_encoding = headers.get("transfer-encoding")
  let content_length = headers.get("content-length")
  guard transfer_encoding is None || content_length is None else {
    raise download_error(
      url, "HTTP response contains both Transfer-Encoding and Content-Length",
    )
  }
  match transfer_encoding {
    Some(value) => {
      guard value.trim().to_owned().to_lower() == "chunked" else {
        raise download_error(
          url, "HTTP response uses an unsupported transfer encoding",
        )
      }
      self.read_chunked_body(url, max_bytes)
    }
    None =>
      match content_length {
        Some(value) => {
          let length = match parse_unsigned_int64(value.trim().to_owned(), 10) {
            Some(length) => length
            None =>
              raise download_error(
                url, "HTTP response has an invalid Content-Length",
              )
          }
          guard length <= max_bytes && length <= 0x7fffffffL else {
            raise download_error(
              url,
              "Download of \{url} exceeded maximum size of \{max_bytes} bytes (Content-Length: \{length}).",
            )
          }
          self.read_exactly(url, length.to_int())
        }
        None => self.read_to_end(url, max_bytes)
      }
  }
}

///|
async fn SafeDownloadConnection::read_response(
  self : SafeDownloadConnection,
  url : String,
  max_bytes : Int64,
) -> HttpResponse {
  for ;; {
    let status_line = self.read_line(url, SAFE_DOWNLOAD_MAX_LINE_BYTES)
    let (status_code, reason) = safe_download_status_line(status_line, url)
    let headers = self.read_headers(url)
    if status_code >= 100 && status_code < 200 && status_code != 101 {
      continue
    }
    guard status_code != 101 else {
      raise download_error(
        url, "HTTP protocol upgrades are not supported for downloads",
      )
    }
    let body = self.read_response_body(url, status_code, headers, max_bytes)
    return HttpResponse::new(status_code~, reason~, headers~, body~)
  }
}

///|
async fn safe_download_open_socket(
  target : SafeDownloadTarget,
  address : @socket.Addr,
) -> SafeDownloadSocket {
  let tcp = @socket.Tcp::connect(address)
  if target.scheme == "https" {
    try @tls.Tls::client(tcp, host=target.hostname) catch {
      error => {
        tcp.close()
        raise error
      }
    } noraise {
      tls => SafeDownloadTls(tcp, tls)
    }
  } else {
    SafeDownloadPlain(tcp)
  }
}

///|
/// Fetch using an address that has already passed the resolved-address policy.
async fn safe_native_download_fetch_at(
  request : HttpRequest,
  target : SafeDownloadTarget,
  address : @socket.Addr,
  max_bytes : Int64,
) -> HttpResponse {
  let socket = safe_download_open_socket(target, address)
  defer socket.close()
  socket.write(@utf8.encode(safe_download_request_text(request, target)))
  let connection = SafeDownloadConnection::{ socket, buffered: b"", offset: 0 }
  connection.read_response(request.url, max_bytes)
}

///|
async fn safe_native_download_fetch(
  request : HttpRequest,
  max_bytes : Int64,
) -> HttpResponse {
  let target = safe_download_target(request.url)
  let address = @socket.Addr::resolve(target.hostname, port=target.port)
  validate_resolved_download_address(target.hostname, address)
  safe_native_download_fetch_at(request, target, address, max_bytes)
}

///|
priv struct SafeNativeDownloadTransport {
  max_bytes : Int64
}

///|
impl HttpTransport for SafeNativeDownloadTransport with fn fetch(self, request) {
  safe_native_download_fetch(request, self.max_bytes)
}

///|
impl HttpTransport for SafeNativeDownloadTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("safe native download transport does not support streaming requests")
}

///|
fn safe_native_download_transport(max_bytes : Int64) -> &HttpTransport {
  SafeNativeDownloadTransport::{ max_bytes, }
}

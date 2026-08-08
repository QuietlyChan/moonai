///|
priv struct DownloadTestStream {
  closed : Ref[Bool]
}

///|
impl HttpStreamResponse for DownloadTestStream with fn status_code(_self) -> Int {
  200
}

///|
impl HttpStreamResponse for DownloadTestStream with fn reason(_self) -> String {
  "OK"
}

///|
impl HttpStreamResponse for DownloadTestStream with fn headers(_self) -> Map[
  String,
  String,
] {
  Map([])
}

///|
impl HttpStreamResponse for DownloadTestStream with fn read_until(
  _self,
  _separator,
) {
  None
}

///|
impl HttpStreamResponse for DownloadTestStream with fn read_all(_self) {
  b""
}

///|
impl HttpStreamResponse for DownloadTestStream with fn close(self) {
  self.closed.val = true
}

///|
priv struct DownloadTestTransport {
  responses : Map[String, HttpResponse]
  requests : Array[HttpRequest]
  stream : DownloadTestStream
}

///|
impl HttpTransport for DownloadTestTransport with fn fetch(self, request) {
  self.requests.push(request)
  self.responses
  .get(self.requests[self.requests.length() - 1].url)
  .unwrap_or(HttpResponse::text(status_code=404, body="missing"))
}

///|
impl HttpTransport for DownloadTestTransport with fn fetch_stream(
  self,
  _request,
) {
  self.stream as &HttpStreamResponse
}

///|
fn assert_download_blocked(url : String) -> Unit raise {
  try validate_download_url(url) catch {
    DownloadError(..) => return
  } noraise {
    _ => fail("expected URL to be blocked: \{url}")
  }
}

///|
fn assert_download_allowed(url : String) -> Unit raise {
  try validate_download_url(url) catch {
    error =>
      fail("unexpected download validation error: \{@debug.to_string(error)}")
  } noraise {
    _ => ()
  }
}

///|
test "download URL validation blocks internal and unsupported targets" {
  for
    url in [
      "http://localhost/file", "http://localhost./file", "http://service.local/file",
      "http://service.localhost/file", "http://127.0.0.1/file", "http://2130706433/file",
      "http://0x7f000001/file", "http://10.0.0.1/file", "http://172.16.0.1/file",
      "http://169.254.169.254/latest/meta-data/", "http://[::1]/file", "http://[fc00::1]/file",
      "http://[::ffff:127.0.0.1]/file", "file:///etc/passwd", "ftp://example.com/file",
      "https://example.com:70000/file", "https://example.com/bad path", "https://example.com/bad\r\nheader",
      "not-a-url",
    ] {
    assert_download_blocked(url)
  }
  assert_download_allowed("https://8.8.8.8/file")
  assert_download_allowed("https://example.com./image.png")
  assert_download_allowed("http://[2606:4700::1]/file")
  assert_download_allowed("data:text/plain;base64,aGVsbG8=")
  assert_download_allowed("DATA:text/plain,hello")
}

///|
async test "download follows safe relative redirects" {
  let transport = DownloadTestTransport::{
    responses: {
      "https://example.com/assets/source": HttpResponse::text(
        status_code=302,
        body="",
        headers={ "Location": "./image.png" },
      ),
      "https://example.com/assets/image.png": HttpResponse::text(
        status_code=200,
        body="PNG",
        headers={ "content-type": "image/png" },
      ),
    },
    requests: [],
    stream: DownloadTestStream::{ closed: Ref(false) },
  }
  let result = download_file(
    provider_name="test",
    url="https://example.com/assets/source",
    retry_policy=@provider.RetryPolicy::none(),
    transport~,
  )
  assert_eq(result.data, @utf8.encode("PNG"))
  assert_eq(result.media_type, "image/png")
  assert_eq(transport.requests.length(), 2)
  assert_eq(transport.requests[1].url, "https://example.com/assets/image.png")
}

///|
async test "download decodes Base64 and percent-encoded data URLs without transport" {
  let transport = DownloadTestTransport::{
    responses: Map([]),
    requests: [],
    stream: DownloadTestStream::{ closed: Ref(false) },
  }
  let base64_result = download_file(
    provider_name="test",
    url="data:text/plain;base64,aGVsbG8=",
    retry_policy=@provider.RetryPolicy::none(),
    transport~,
  )
  assert_eq(base64_result.data, @utf8.encode("hello"))
  assert_eq(base64_result.media_type, "text/plain")
  let percent_result = download_file(
    provider_name="test",
    url="data:application/octet-stream,%00%2B%FF",
    retry_policy=@provider.RetryPolicy::none(),
    transport~,
  )
  assert_eq(percent_result.data, b"\x00+\xff")
  assert_eq(percent_result.media_type, "application/octet-stream")
  assert_eq(transport.requests.length(), 0)
}

///|
async test "download rejects malformed data URLs and oversized content" {
  let transport = DownloadTestTransport::{
    responses: {
      "https://example.com/header": HttpResponse::new(
        status_code=200,
        reason="OK",
        headers={ "content-length": "6" },
        body=b"small",
      ),
      "https://example.com/body": HttpResponse::new(
        status_code=200,
        reason="OK",
        body=b"larger",
      ),
    },
    requests: [],
    stream: DownloadTestStream::{ closed: Ref(false) },
  }
  for
    url in [
      "data:text/plain;base64,not-base64!", "data:text/plain,broken%2", "data:text/plain,hello",
      "https://example.com/header", "https://example.com/body",
    ] {
    try
      download_file(
        provider_name="test",
        url~,
        max_bytes=4L,
        retry_policy=@provider.RetryPolicy::none(),
        transport~,
      )
    catch {
      @provider_utils.DownloadError(..) => continue
      error => fail("unexpected download error: \{@debug.to_string(error)}")
    } noraise {
      _ => fail("expected download to fail: \{url}")
    }
  }
}

///|
async test "download rejects a redirect to a private address before requesting it" {
  let transport = DownloadTestTransport::{
    responses: {
      "https://example.com/source": HttpResponse::text(
        status_code=302,
        body="",
        headers={ "location": "http://127.0.0.1/secret" },
      ),
    },
    requests: [],
    stream: DownloadTestStream::{ closed: Ref(false) },
  }
  try
    download_file(
      provider_name="test",
      url="https://example.com/source",
      retry_policy=@provider.RetryPolicy::none(),
      transport~,
    )
  catch {
    @provider_utils.DownloadError(url~, message~, ..) => {
      assert_eq(url, "http://127.0.0.1/secret")
      assert_true(message.contains("not allowed"))
    }
    error => fail("unexpected download error: \{@debug.to_string(error)}")
  } noraise {
    _ => fail("expected the private redirect to be rejected")
  }
  assert_eq(transport.requests.length(), 1)
}

///|
async test "download drops credentials on a cross-origin redirect" {
  let transport = DownloadTestTransport::{
    responses: {
      "https://example.com/source": HttpResponse::text(
        status_code=302,
        body="",
        headers={ "location": "https://cdn.example.com/file" },
      ),
      "https://cdn.example.com/file": HttpResponse::text(
        status_code=200,
        body="ok",
      ),
    },
    requests: [],
    stream: DownloadTestStream::{ closed: Ref(false) },
  }
  let _ = download_file(
    provider_name="test",
    url="https://example.com/source",
    headers={
      "Authorization": "Bearer secret",
      "User-Agent": "moon-test",
      "Host": "metadata.internal",
      "Cookie": "session=secret",
      "X-Forwarded-For": "127.0.0.1",
    },
    retry_policy=@provider.RetryPolicy::none(),
    transport~,
  )
  assert_eq(
    transport.requests[0].headers.get("Authorization"),
    Some("Bearer secret"),
  )
  assert_eq(transport.requests[0].headers.get("Host"), None)
  assert_eq(transport.requests[0].headers.get("Cookie"), None)
  assert_eq(transport.requests[0].headers.get("X-Forwarded-For"), None)
  assert_eq(transport.requests[1].headers.get("Authorization"), None)
  assert_eq(transport.requests[1].headers.get("User-Agent"), Some("moon-test"))
}

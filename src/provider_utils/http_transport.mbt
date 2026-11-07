///|
/// HTTP methods used by provider transports.
#derive(Debug, Eq)
pub(all) enum HttpMethod {
  HttpGet
  HttpPost
  HttpDelete
}

///|
/// Runtime-independent provider HTTP request.
///
/// The byte body allows JSON, multipart, and binary requests to share one
/// transport boundary. GET requests use an empty body.
#derive(Debug, Eq)
pub(all) struct HttpRequest {
  meth : HttpMethod
  url : String
  headers : Map[String, String]
  body : Bytes
}

///|
/// Construct a transport request.
pub fn HttpRequest::new(
  meth~ : HttpMethod,
  url~ : String,
  headers? : Map[String, String] = Map([]),
  body? : Bytes = b"",
) -> HttpRequest {
  { meth, url, headers: copy_headers(headers), body, }
}

///|
/// Construct a GET request.
pub fn HttpRequest::get(
  url~ : String,
  headers? : Map[String, String] = Map([]),
) -> HttpRequest {
  HttpRequest::new(meth=HttpGet, url~, headers~)
}

///|
/// Construct a POST request.
pub fn HttpRequest::post(
  url~ : String,
  headers? : Map[String, String] = Map([]),
  body~ : Bytes,
) -> HttpRequest {
  HttpRequest::new(meth=HttpPost, url~, headers~, body~)
}

///|
/// Construct a DELETE request without a body.
pub fn HttpRequest::delete(
  url~ : String,
  headers? : Map[String, String] = Map([]),
) -> HttpRequest {
  HttpRequest::new(meth=HttpDelete, url~, headers~)
}

///|
/// Decode a request body as UTF-8 for tests and request middleware.
pub fn HttpRequest::body_text(self : HttpRequest) -> String raise {
  @utf8.decode(self.body)
}

///|
/// Fully buffered response returned by `HttpTransport::fetch`.
#derive(Debug, Eq)
pub(all) struct HttpResponse {
  status_code : Int32
  reason : String
  headers : Map[String, String]
  body : Bytes
}

///|
/// Construct a buffered transport response.
pub fn HttpResponse::new(
  status_code~ : Int32,
  body~ : Bytes,
  reason? : String = "",
  headers? : Map[String, String] = Map([]),
) -> HttpResponse {
  { status_code, reason, headers: copy_headers(headers), body, }
}

///|
/// Construct a UTF-8 text response.
pub fn HttpResponse::text(
  status_code~ : Int32,
  body~ : String,
  reason? : String = "",
  headers? : Map[String, String] = Map([]),
) -> HttpResponse {
  HttpResponse::new(status_code~, body=@utf8.encode(body), reason~, headers~)
}

///|
/// Whether the response has a successful HTTP status.
pub fn HttpResponse::is_success(self : HttpResponse) -> Bool {
  self.status_code >= 200 && self.status_code < 300
}

///|
/// Decode a buffered response body as UTF-8.
pub fn HttpResponse::body_text(self : HttpResponse) -> String raise {
  @utf8.decode(self.body)
}

///|
/// Runtime-independent streaming HTTP response.
pub(open) trait HttpStreamResponse {
  fn status_code(Self) -> Int32
  fn reason(Self) -> String
  fn headers(Self) -> Map[String, String]
  async fn read_until(Self, String) -> String?
  async fn read_all(Self) -> Bytes
  fn close(Self) -> Unit
}

///|
/// Injectable provider HTTP boundary, equivalent to AI SDK's configurable
/// `FetchFunction` while retaining explicit streaming support in MoonBit.
pub(open) trait HttpTransport {
  async fn fetch(Self, HttpRequest) -> HttpResponse
  async fn fetch_stream(Self, HttpRequest) -> &HttpStreamResponse
}

///|
/// Transport-level support for writing a request body incrementally
/// (AI SDK streaming file uploads, #20036).
///
/// `prefix` is written before the streamed payload and `suffix` after it —
/// multipart file fields carry trailing form data and the closing boundary.
/// `content_length` is the exact total body size; callers must supply it
/// (multipart plans derive it from the stream's `size_hint_bytes`), which
/// lets transports set Content-Length instead of relying on chunked
/// encoding.
pub(open) trait StreamingBodyTransport: HttpTransport {
  async fn fetch_streaming_body(
    Self,
    meth~ : HttpMethod,
    url~ : String,
    headers~ : Map[String, String],
    prefix~ : Bytes,
    body~ : &@provider.UploadByteStream,
    suffix~ : Bytes,
    content_length~ : Int64,
  ) -> HttpResponse
}

///|
/// Convert provider header maps to the case-insensitive map used by
/// `moonbitlang/async/http`.
fn to_http_headers(
  headers : Map[String, String],
) -> Map[@http.CaseInsensitiveString, String] {
  let result : Map[@http.CaseInsensitiveString, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    result[@http.CaseInsensitiveString(key)] = value
  }
  result
}

///|
/// Convert `moonbitlang/async/http` headers back to provider header maps.
///
/// Header names are normalized to lower case, matching the case-insensitive
/// lookup behavior providers expect.
fn from_http_headers(
  headers : Map[@http.CaseInsensitiveString, String],
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    result[key.to_string().to_lower()] = value
  }
  result
}

///|
priv struct NativeHttpStreamResponse {
  client : @http.Client
  response : @http.Response
}

///|
impl HttpStreamResponse for NativeHttpStreamResponse with fn status_code(self) -> Int32 {
  self.response.code
}

///|
impl HttpStreamResponse for NativeHttpStreamResponse with fn reason(self) -> String {
  self.response.reason
}

///|
impl HttpStreamResponse for NativeHttpStreamResponse with fn headers(self) -> Map[
  String,
  String,
] {
  copy_headers(from_http_headers(self.response.headers))
}

///|
impl HttpStreamResponse for NativeHttpStreamResponse with fn read_until(
  self,
  separator,
) {
  self.client.read_until(separator)
}

///|
impl HttpStreamResponse for NativeHttpStreamResponse with fn read_all(self) {
  self.client.read_all().binary()
}

///|
impl HttpStreamResponse for NativeHttpStreamResponse with fn close(self) {
  self.client.close()
}

///|
/// Native transport backed by `moonbitlang/async/http`.
pub struct NativeHttpTransport {}

///|
/// Construct the built-in native HTTP transport.
pub fn NativeHttpTransport::new() -> NativeHttpTransport {
  NativeHttpTransport::{ }
}

///|
impl HttpTransport for NativeHttpTransport with fn fetch(_self, request) {
  let (response, body) = match request.meth {
    HttpGet => @http.get(request.url, headers=to_http_headers(request.headers))
    HttpPost =>
      @http.post(
        request.url,
        request.body,
        headers=to_http_headers(request.headers),
      )
    HttpDelete => native_delete(request.url, request.headers)
  }
  HttpResponse::new(
    status_code=response.code,
    reason=response.reason,
    headers=from_http_headers(response.headers),
    body=body.binary(),
  )
}

///|
/// Split an absolute HTTP(S) URL into the client origin and request path.
fn absolute_url_parts(url : String) -> (String, String) raise {
  let scheme = if url.has_prefix("https://") {
    "https"
  } else if url.has_prefix("http://") {
    "http"
  } else {
    fail("URL must use http or https")
  }
  let authority = url_authority(url).unwrap_or_else(() => {
    fail("URL must be absolute")
  })
  let origin = "\{scheme}://\{authority}"
  let suffix = url[origin.length():].to_owned()
  let path = if suffix == "" {
    "/"
  } else if suffix.has_prefix("?") {
    "/" + suffix
  } else {
    suffix
  }
  (origin, path)
}

///|
async fn native_delete(
  url : String,
  headers : Map[String, String],
) -> (@http.Response, &@io.Data) {
  let (origin, target) = absolute_url_parts(url)
  let client = @http.Client(origin)
  defer client.close()
  client.request(@http.Delete, target, extra_headers=to_http_headers(headers))
  let response = client.end_request()
  let body = client.read_all()
  (response, body)
}

///|
impl HttpTransport for NativeHttpTransport with fn fetch_stream(_self, request) {
  guard request.meth == HttpPost else {
    fail("native streaming transport currently supports POST requests only")
  }
  let client = @http.post_stream(
    request.url,
    headers=to_http_headers(request.headers),
  )
  // The response wrapper takes ownership on success; close only on failure.
  errdefer client.close()
  client.write(request.body)
  let response = client.end_request()
  NativeHttpStreamResponse::{ client, response, } as &HttpStreamResponse
}

///|
impl StreamingBodyTransport for NativeHttpTransport with fn fetch_streaming_body(
  _self,
  meth~,
  url~,
  headers~,
  prefix~,
  body~,
  suffix~,
  content_length~,
) -> HttpResponse {
  guard meth == HttpPost else {
    fail("native streaming-body transport supports POST requests only")
  }
  let (origin, path) = absolute_url_parts(url)
  let client = @http.Client(origin, headers=to_http_headers(headers))
  // The response wrapper takes ownership on success; close only on failure.
  errdefer client.close()
  client.request(
    @http.Post,
    path,
    extra_headers=to_http_headers({
      "Content-Length": content_length.to_string(),
    }),
  )
  client.write(prefix)
  for ;; {
    match body.read_chunk() {
      Some(chunk) => client.write(chunk)
      None => break
    }
  }
  client.write(suffix)
  let response = client.end_request()
  HttpResponse::new(
    status_code=response.code,
    reason=response.reason,
    headers=from_http_headers(response.headers),
    body=client.read_all().binary(),
  )
}

///|
/// Return the default native transport as an injectable trait object.
pub fn native_http_transport() -> &HttpTransport {
  NativeHttpTransport::new()
}

///|
/// Return the default native transport with streaming-body upload support.
pub fn native_streaming_body_transport() -> &StreamingBodyTransport {
  NativeHttpTransport::new()
}

///|
pub extend HttpMethod with Debug::{to_repr}

///|
pub extend HttpMethod with Eq::{not_equal, equal}

///|
pub extend HttpRequest with Debug::{to_repr}

///|
pub extend HttpRequest with Eq::{not_equal, equal}

///|
pub extend HttpResponse with Debug::{to_repr}

///|
pub extend HttpResponse with Eq::{not_equal, equal}

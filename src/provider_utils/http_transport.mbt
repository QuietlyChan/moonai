///|
/// HTTP methods used by provider transports.
pub(all) enum HttpMethod {
  HttpGet
  HttpPost
} derive(Debug, Eq)

///|
/// Runtime-independent provider HTTP request.
///
/// The byte body allows JSON, multipart, and binary requests to share one
/// transport boundary. GET requests use an empty body.
pub(all) struct HttpRequest {
  meth : HttpMethod
  url : String
  headers : Map[String, String]
  body : Bytes
} derive(Debug, Eq)

///|
/// Construct a transport request.
pub fn HttpRequest::new(
  meth~ : HttpMethod,
  url~ : String,
  headers? : Map[String, String] = Map([]),
  body? : Bytes = b"",
) -> HttpRequest {
  { meth, url, headers: copy_headers(headers), body }
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
/// Decode a request body as UTF-8 for tests and request middleware.
pub fn HttpRequest::body_text(self : HttpRequest) -> String raise {
  @utf8.decode(self.body)
}

///|
/// Fully buffered response returned by `HttpTransport::fetch`.
pub(all) struct HttpResponse {
  status_code : Int
  reason : String
  headers : Map[String, String]
  body : Bytes
} derive(Debug, Eq)

///|
/// Construct a buffered transport response.
pub fn HttpResponse::new(
  status_code~ : Int,
  body~ : Bytes,
  reason? : String = "",
  headers? : Map[String, String] = Map([]),
) -> HttpResponse {
  { status_code, reason, headers: copy_headers(headers), body }
}

///|
/// Construct a UTF-8 text response.
pub fn HttpResponse::text(
  status_code~ : Int,
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
  fn status_code(Self) -> Int
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
priv struct NativeHttpStreamResponse {
  client : @http.Client
  response : @http.Response
}

///|
impl HttpStreamResponse for NativeHttpStreamResponse with fn status_code(self) -> Int {
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
  copy_headers(self.response.headers)
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
  NativeHttpTransport::{  }
}

///|
impl HttpTransport for NativeHttpTransport with fn fetch(_self, request) {
  let (response, body) = match request.meth {
    HttpGet => @http.get(request.url, headers=request.headers)
    HttpPost => @http.post(request.url, request.body, headers=request.headers)
  }
  HttpResponse::new(
    status_code=response.code,
    reason=response.reason,
    headers=response.headers,
    body=body.binary(),
  )
}

///|
impl HttpTransport for NativeHttpTransport with fn fetch_stream(_self, request) {
  guard request.meth == HttpPost else {
    fail("native streaming transport currently supports POST requests only")
  }
  let client = @http.post_stream(request.url, headers=request.headers)
  try {
    client.write(request.body)
    let response = client.end_request()
    NativeHttpStreamResponse::{ client, response } as &HttpStreamResponse
  } catch {
    error => {
      client.close()
      raise error
    }
  }
}

///|
/// Return the default native transport as an injectable trait object.
pub fn native_http_transport() -> &HttpTransport {
  NativeHttpTransport::new()
}

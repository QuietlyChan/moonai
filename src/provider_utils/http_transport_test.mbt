///|
priv struct MockHttpStreamResponse {
  status : Int
  reason_text : String
  response_headers : Map[String, String]
  chunks : Array[String]
  next_chunk : Ref[Int]
  closed : Ref[Bool]
}

///|
fn MockHttpStreamResponse::new(
  chunks : Array[String],
  status? : Int = 200,
  reason? : String = "OK",
  headers? : Map[String, String] = Map([]),
) -> MockHttpStreamResponse {
  {
    status,
    reason_text: reason,
    response_headers: copy_headers(headers),
    chunks,
    next_chunk: Ref(0),
    closed: Ref(false),
  }
}

///|
impl HttpStreamResponse for MockHttpStreamResponse with fn status_code(self) {
  self.status
}

///|
impl HttpStreamResponse for MockHttpStreamResponse with fn reason(self) {
  self.reason_text
}

///|
impl HttpStreamResponse for MockHttpStreamResponse with fn headers(self) {
  copy_headers(self.response_headers)
}

///|
impl HttpStreamResponse for MockHttpStreamResponse with fn read_until(
  self,
  _separator,
) {
  guard self.next_chunk.val < self.chunks.length() else { return None }
  let chunk = self.chunks[self.next_chunk.val]
  self.next_chunk.val = self.next_chunk.val + 1
  Some(chunk)
}

///|
impl HttpStreamResponse for MockHttpStreamResponse with fn read_all(self) {
  let remaining : Array[String] = []
  while self.next_chunk.val < self.chunks.length() {
    remaining.push(self.chunks[self.next_chunk.val])
    self.next_chunk.val = self.next_chunk.val + 1
  }
  @utf8.encode(remaining.join("\n"))
}

///|
impl HttpStreamResponse for MockHttpStreamResponse with fn close(self) {
  self.closed.val = true
}

///|
priv struct MockHttpTransport {
  buffered_response : HttpResponse
  stream_response : MockHttpStreamResponse
  buffered_requests : Array[HttpRequest]
  stream_requests : Array[HttpRequest]
}

///|
fn MockHttpTransport::new(
  buffered_response : HttpResponse,
  stream_response : MockHttpStreamResponse,
) -> MockHttpTransport {
  {
    buffered_response,
    stream_response,
    buffered_requests: [],
    stream_requests: [],
  }
}

///|
impl HttpTransport for MockHttpTransport with fn fetch(self, request) {
  self.buffered_requests.push(request)
  self.buffered_response
}

///|
impl HttpTransport for MockHttpTransport with fn fetch_stream(self, request) {
  self.stream_requests.push(request)
  self.stream_response as &HttpStreamResponse
}

///|
async test "HttpTransport injects buffered JSON requests" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(
      status_code=200,
      body="{\"id\":\"response-1\",\"value\":42}",
      headers={ "x-request-id": "request-1" },
    ),
    stream,
  )
  let response = post_json(
    provider_name="mock",
    url="https://example.test/v1/generate",
    headers={ "Authorization": "Bearer test-key" },
    body={ "prompt": "hello" },
    retry_policy=@provider.RetryPolicy::none(),
    transport~,
  )
  assert_eq(response.value, ({ "id": "response-1", "value": 42 } : Json))
  assert_eq(response.response.id, Some("response-1"))
  assert_eq(response.response.headers.get("x-request-id"), Some("request-1"))
  assert_eq(transport.buffered_requests.length(), 1)
  let request = transport.buffered_requests[0]
  assert_eq(request.meth, HttpPost)
  assert_eq(request.url, "https://example.test/v1/generate")
  assert_eq(request.headers.get("Authorization"), Some("Bearer test-key"))
  assert_eq(@json.parse(request.body_text()), ({ "prompt": "hello" } : Json))
}

///|
async test "HttpTransport injects streaming SSE requests and closes responses" {
  let stream = MockHttpStreamResponse::new(
    ["data: first", "", "data: second", "", "data: [DONE]", ""],
    headers={ "content-type": "text/event-stream" },
  )
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}"),
    stream,
  )
  let buffer = EventSourceBuffer::new()
  let payloads : Array[String] = []
  let events : Array[@provider.StreamEvent] = []
  let decode_payload = payload => {
    if payload == "[DONE]" {
      DecodeBatch::empty(true)
    } else {
      payloads.push(payload)
      { events: [], consumed_event: true, done: false }
    }
  }
  let result = post_json_sse(
    provider_name="mock",
    url="https://example.test/v1/stream",
    headers={ "Authorization": "Bearer stream-key" },
    body={ "stream": true },
    retry_policy=@provider.RetryPolicy::none(),
    feed_line=raw => {
      match buffer.feed_line(raw) {
        Some(payload) => decode_payload(payload)
        None => DecodeBatch::empty(false)
      }
    },
    flush_buffered=() => {
      match buffer.flush() {
        Some(payload) => decode_payload(payload)
        None => DecodeBatch::empty(false)
      }
    },
    response=() => payloads.join(","),
    transport~,
    on_event=event => events.push(event),
  )
  assert_eq(result.value, "first,second")
  assert_eq(result.response.status_code, Some(200))
  assert_eq(transport.stream_requests.length(), 1)
  assert_eq(transport.stream_requests[0].meth, HttpPost)
  assert_eq(
    transport.stream_requests[0].headers.get("Authorization"),
    Some("Bearer stream-key"),
  )
  assert_true(events.length() == 1 && events[0] is @provider.StreamStart)
  assert_true(stream.closed.val)
}

///|
async test "SSE provider errors preserve HTTP diagnostics" {
  let stream = MockHttpStreamResponse::new(["data: provider-error", ""], headers={
    "content-type": "text/event-stream",
    "x-request-id": "sse-error-1",
  })
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}"),
    stream,
  )
  try
    post_json_sse(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers={ "Authorization": "Bearer stream-key" },
      body={ "stream": true, "prompt": "hello" },
      retry_policy=@provider.RetryPolicy::none(),
      feed_line=_raw => {
        raise @provider_utils.SseProviderError(
          message="quota exceeded",
          status_code=429,
          response_body="{\"type\":\"insufficient_quota\"}",
          is_retryable=true,
        )
      },
      flush_buffered=() => DecodeBatch::empty(false),
      response=() => "unreachable",
      transport~,
      on_event=_event => (),
    )
    |> ignore
  catch {
    @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers~,
      status_code~,
      response_headers~,
      response_body~,
      is_retryable~
    ) => {
      assert_eq(message, "quota exceeded")
      assert_eq(url, "https://example.test/v1/stream")
      assert_true(request_body.contains("\"prompt\":\"hello\""))
      assert_eq(request_headers["Authorization"], "Bearer stream-key")
      assert_eq(status_code, 429)
      assert_eq(response_headers["x-request-id"], "sse-error-1")
      assert_true(response_body.contains("insufficient_quota"))
      assert_eq(is_retryable, true)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed SSE provider error")
  }
  assert_true(stream.closed.val)
}

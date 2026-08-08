///|
priv struct MockHttpStreamResponse {
  status : Int
  reason_text : String
  response_headers : Map[String, String]
  chunks : Array[String]
  delays_ms : Array[Int]
  next_chunk : Ref[Int]
  closed : Ref[Bool]
}

///|
fn MockHttpStreamResponse::new(
  chunks : Array[String],
  status? : Int = 200,
  reason? : String = "OK",
  headers? : Map[String, String] = Map([]),
  delays_ms? : Array[Int] = [],
) -> MockHttpStreamResponse {
  {
    status,
    reason_text: reason,
    response_headers: copy_headers(headers),
    chunks,
    delays_ms,
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
  let index = self.next_chunk.val
  if index < self.delays_ms.length() && self.delays_ms[index] > 0 {
    @async.sleep(self.delays_ms[index])
  }
  let chunk = self.chunks[index]
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
async test "buffered invalid JSON retains API call diagnostics" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{not-json", headers={
      "x-request-id": "request-invalid-json",
    }),
    stream,
  )
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers={ "Authorization": "Bearer test-key" },
      body={ "prompt": "hello" },
      retry_policy=@provider.RetryPolicy::none(),
      transport~,
    )
  catch {
    @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers~,
      status_code~,
      response_headers~,
      response_body~,
      is_retryable~,
      data~,
      cause~
    ) => {
      assert_eq(message, "Invalid JSON response")
      assert_eq(url, "https://example.test/v1/generate")
      assert_eq(@json.parse(request_body), ({ "prompt": "hello" } : Json))
      assert_eq(request_headers.get("Authorization"), Some("Bearer test-key"))
      assert_eq(status_code, Some(200))
      assert_eq(
        response_headers.get("x-request-id"),
        Some("request-invalid-json"),
      )
      assert_eq(response_body, "{not-json")
      assert_false(is_retryable)
      assert_eq(data, None)
      assert_true(cause.unwrap_or("") != "")
    }
    error => fail("unexpected JSON decode error: \{error}")
  } noraise {
    _ => fail("expected invalid JSON to become APICallError")
  }
}

///|
async test "buffered JSON validators retain parsed response data" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{\"value\":\"wrong\"}", headers={
      "x-request-id": "request-invalid-schema",
    }),
    stream,
  )
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers=Map([]),
      body=Json::empty_object(),
      retry_policy=@provider.RetryPolicy::none(),
      validate_response=value => {
        guard value is { "value": Number(_, ..), .. } else {
          raise @provider.InvalidResponseDataError(
            message="expected numeric value",
            data=value,
          )
        }
      },
      transport~,
    )
  catch {
    @provider.APICallError(
      message~,
      status_code~,
      response_headers~,
      response_body~,
      is_retryable~,
      data~,
      cause~,
      ..
    ) => {
      assert_eq(message, "Invalid JSON response")
      assert_eq(status_code, Some(200))
      assert_eq(
        response_headers.get("x-request-id"),
        Some("request-invalid-schema"),
      )
      assert_eq(response_body, "{\"value\":\"wrong\"}")
      assert_false(is_retryable)
      assert_true(data is Some({ "value": "wrong", .. }))
      assert_true(cause.unwrap_or("").contains("expected numeric value"))
    }
    error => fail("unexpected JSON validation error: \{error}")
  } noraise {
    _ => fail("expected schema validation to become APICallError")
  }
}

///|
async test "successful JSON handlers preserve results and wrap failures" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{\"value\":42}", headers={
      "x-request-id": "request-handler",
    }),
    stream,
  )
  let response = post_json(
    provider_name="mock",
    url="https://example.test/v1/generate",
    headers=Map([]),
    body={ "prompt": "hello" },
    retry_policy=@provider.RetryPolicy::none(),
    transport~,
  )
  let value = handleJsonResponse(response, json => {
    match json {
      { "value": Number(value, ..), .. } => value.to_int()
      _ => fail("missing value")
    }
  })
  assert_eq(value, 42)
  try
    handle_json_response(response, json => {
      guard json is Null else {
        raise @provider.InvalidResponseDataError(
          message="provider conversion failed",
          data=json,
        )
      }
    })
  catch {
    @provider.APICallError(
      message~,
      status_code~,
      response_headers~,
      data~,
      cause~,
      ..
    ) => {
      assert_eq(message, "Failed to process successful response")
      assert_eq(status_code, Some(200))
      assert_eq(response_headers.get("x-request-id"), Some("request-handler"))
      assert_true(data is Some({ "value": 42, .. }))
      assert_true(cause.unwrap_or("").contains("provider conversion failed"))
    }
    error => fail("unexpected successful-response handler error: \{error}")
  } noraise {
    _ => fail("expected the handler failure to become APICallError")
  }
}

///|
async test "failed JSON response handlers preserve API call diagnostics" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(
      status_code=400,
      body="{\"error\":{\"message\":\"invalid request\"}}",
      headers={ "x-request-id": "request-error-handler" },
    ),
    stream,
  )
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers={ "Authorization": "Bearer test-key" },
      body={ "prompt": "hello" },
      retry_policy=@provider.RetryPolicy::none(),
      error_to_message=value => {
        raise @provider.InvalidResponseDataError(
          message="provider error decoder failed",
          data=value,
        )
      },
      transport~,
    )
  catch {
    @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers~,
      status_code~,
      response_headers~,
      response_body~,
      is_retryable~,
      data~,
      cause~
    ) => {
      assert_eq(message, "Failed to process error response")
      assert_eq(url, "https://example.test/v1/generate")
      assert_eq(@json.parse(request_body), ({ "prompt": "hello" } : Json))
      assert_eq(request_headers.get("Authorization"), Some("Bearer test-key"))
      assert_eq(status_code, Some(400))
      assert_eq(
        response_headers.get("x-request-id"),
        Some("request-error-handler"),
      )
      assert_eq(response_body, "{\"error\":{\"message\":\"invalid request\"}}")
      assert_false(is_retryable)
      assert_eq(data, None)
      assert_true(cause.unwrap_or("").contains("provider error decoder failed"))
    }
    error => fail("unexpected failed-response handler error: \{error}")
  } noraise {
    _ => fail("expected the failed-response handler error to be wrapped")
  }
}

///|
async test "response handlers preserve cancellation and existing API call errors" {
  let stream = MockHttpStreamResponse::new([])
  let successful_transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{\"value\":42}"),
    stream,
  )
  let cancellation_token = @provider.CancellationToken::new()
  cancellation_token.cancel()
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers=Map([]),
      body=Json::empty_object(),
      retry_policy=@provider.RetryPolicy::none(),
      validate_response=_ => cancellation_token.check(),
      transport=successful_transport,
    )
  catch {
    @provider.CancellationError => ()
    error => fail("unexpected successful-response cancellation error: \{error}")
  } noraise {
    _ => fail("expected successful-response cancellation to propagate")
  }
  let failed_transport = MockHttpTransport::new(
    HttpResponse::text(status_code=400, body="{\"error\":\"bad\"}"),
    stream,
  )
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers=Map([]),
      body=Json::empty_object(),
      retry_policy=@provider.RetryPolicy::none(),
      error_to_message=_ => {
        raise @provider.APICallError(
          message="custom API call error",
          url="https://custom.test/error",
          request_body="custom request",
          request_headers=Map([]),
          status_code=Some(418),
          response_headers=Map([]),
          response_body="custom response",
          is_retryable=false,
          data=Some(({ "custom": true } : Json)),
          cause=Some("custom cause"),
        )
      },
      transport=failed_transport,
    )
  catch {
    @provider.APICallError(
      message~,
      url~,
      request_body~,
      status_code~,
      response_body~,
      data~,
      cause~,
      ..
    ) => {
      assert_eq(message, "custom API call error")
      assert_eq(url, "https://custom.test/error")
      assert_eq(request_body, "custom request")
      assert_eq(status_code, Some(418))
      assert_eq(response_body, "custom response")
      assert_eq(data, Some(({ "custom": true } : Json)))
      assert_eq(cause, Some("custom cause"))
    }
    error => fail("unexpected existing API call error: \{error}")
  } noraise {
    _ => fail("expected the existing API call error to propagate")
  }
}

///|
async test "binary response retry classifier failures use status retryability" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=503, body="{\"error\":\"overloaded\"}", headers={
      "x-request-id": "binary-error-handler",
    }),
    stream,
  )
  try
    post_json_binary(
      provider_name="mock",
      url="https://example.test/v1/audio",
      headers=Map([]),
      body={ "input": "hello" },
      retry_policy=@provider.RetryPolicy::none(),
      is_retryable_response=(_status_code, error) => {
        raise @provider.InvalidResponseDataError(
          message="retry classifier failed",
          data=error.unwrap_or(Json::null()),
        )
      },
      transport~,
    )
  catch {
    @provider.APICallError(
      message~,
      status_code~,
      response_headers~,
      response_body~,
      is_retryable~,
      data~,
      cause~,
      ..
    ) => {
      assert_eq(message, "Failed to process error response")
      assert_eq(status_code, Some(503))
      assert_eq(
        response_headers.get("x-request-id"),
        Some("binary-error-handler"),
      )
      assert_eq(response_body, "{\"error\":\"overloaded\"}")
      assert_true(is_retryable)
      assert_eq(data, None)
      assert_true(cause.unwrap_or("").contains("retry classifier failed"))
    }
    error => fail("unexpected binary failed-response handler error: \{error}")
  } noraise {
    _ => fail("expected the binary retry classifier error to be wrapped")
  }
}

///|
async test "GET failed-response handlers retain an empty request body" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(
      status_code=422,
      body="{\"error\":\"invalid resource\"}",
      headers={ "x-request-id": "get-error-handler" },
    ),
    stream,
  )
  try
    get_json(
      provider_name="mock",
      url="https://example.test/v1/resources/item-1",
      headers=Map([]),
      retry_policy=@provider.RetryPolicy::none(),
      error_to_message=value => {
        raise @provider.InvalidResponseDataError(
          message="GET error decoder failed",
          data=value,
        )
      },
      transport~,
    )
  catch {
    @provider.APICallError(
      message~,
      url~,
      request_body~,
      status_code~,
      response_headers~,
      response_body~,
      is_retryable~,
      cause~,
      ..
    ) => {
      assert_eq(message, "Failed to process error response")
      assert_eq(url, "https://example.test/v1/resources/item-1")
      assert_eq(request_body, "")
      assert_eq(status_code, Some(422))
      assert_eq(response_headers.get("x-request-id"), Some("get-error-handler"))
      assert_eq(response_body, "{\"error\":\"invalid resource\"}")
      assert_false(is_retryable)
      assert_true(cause.unwrap_or("").contains("GET error decoder failed"))
    }
    error => fail("unexpected GET failed-response handler error: \{error}")
  } noraise {
    _ => fail("expected the GET failed-response handler error to be wrapped")
  }
}

///|
async test "buffered JSON responses enforce the shared size limit" {
  let stream = MockHttpStreamResponse::new([])
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}", headers={
      "content-length": "2147483649",
    }),
    stream,
  )
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers=Map([]),
      body=Json::empty_object(),
      retry_policy=@provider.RetryPolicy::none(),
      transport~,
    )
  catch {
    @provider_utils.DownloadError(url~, message~, ..) => {
      assert_eq(url, "https://example.test/v1/generate")
      assert_true(message.contains("Content-Length: 2147483649"))
    }
    error => fail("unexpected response size error: \{error}")
  } noraise {
    _ => fail("expected oversized JSON response to be rejected")
  }
}

///|
async test "SSE failed-response handlers preserve stream diagnostics" {
  let stream = MockHttpStreamResponse::new(
    ["{\"error\":{\"message\":\"rate limited\"}}"],
    status=429,
    reason="Too Many Requests",
    headers={ "x-request-id": "sse-error-handler" },
  )
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}"),
    stream,
  )
  try
    post_json_sse_events(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers={ "Authorization": "Bearer stream-key" },
      body={ "stream": true },
      retry_policy=@provider.RetryPolicy::none(),
      error_to_message=value => {
        raise @provider.InvalidResponseDataError(
          message="SSE error decoder failed",
          data=value,
        )
      },
      start_events=[@provider.StreamStart],
      is_stream_error=event => event is @provider.StreamError(_),
      feed_line=_ => SseDecodeBatch::empty(false),
      flush_buffered=() => SseDecodeBatch::empty(false),
      response=() => "unreachable",
      transport~,
      on_event=_ => (),
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
      is_retryable~,
      data~,
      cause~
    ) => {
      assert_eq(message, "Failed to process error response")
      assert_eq(url, "https://example.test/v1/stream")
      assert_true(request_body.contains("\"stream\":true"))
      assert_eq(request_headers.get("Authorization"), Some("Bearer stream-key"))
      assert_eq(status_code, Some(429))
      assert_eq(response_headers.get("x-request-id"), Some("sse-error-handler"))
      assert_true(response_body.contains("rate limited"))
      assert_true(is_retryable)
      assert_eq(data, None)
      assert_true(cause.unwrap_or("").contains("SSE error decoder failed"))
    }
    error => fail("unexpected SSE failed-response handler error: \{error}")
  } noraise {
    _ => fail("expected the SSE failed-response handler error to be wrapped")
  }
  assert_true(stream.closed.val)
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
      SseDecodeBatch::empty(true)
    } else {
      payloads.push(payload)
      { events: [], consumed_event: true, done: false }
    }
  }
  let result = post_json_sse_events(
    provider_name="mock",
    url="https://example.test/v1/stream",
    headers={ "Authorization": "Bearer stream-key" },
    body={ "stream": true },
    retry_policy=@provider.RetryPolicy::none(),
    start_events=[@provider.StreamStart],
    is_stream_error=event => event is @provider.StreamError(_),
    feed_line=raw => {
      match buffer.feed_line(raw) {
        Some(payload) => decode_payload(payload)
        None => SseDecodeBatch::empty(false)
      }
    },
    flush_buffered=() => {
      match buffer.flush() {
        Some(payload) => decode_payload(payload)
        None => SseDecodeBatch::empty(false)
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
async test "SSE transport runs the protocol finalizer only at normal EOF" {
  let stream = MockHttpStreamResponse::new(["data: partial", ""], headers={
    "content-type": "text/event-stream",
  })
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}"),
    stream,
  )
  let buffer = EventSourceBuffer::new()
  let finalizer_calls = Ref(0)
  let payloads : Array[String] = []
  let events : Array[@provider.StreamEvent] = []
  let result = post_json_sse_events(
    provider_name="mock",
    url="https://example.test/v1/stream",
    headers=Map([]),
    body={ "stream": true },
    idle_timeout_ms=100,
    retry_policy=@provider.RetryPolicy::none(),
    start_events=[@provider.StreamStart],
    is_stream_error=event => event is @provider.StreamError(_),
    feed_line=raw => {
      match buffer.feed_line(raw) {
        Some(payload) => {
          payloads.push(payload)
          { events: [], consumed_event: true, done: false }
        }
        None => SseDecodeBatch::empty(false)
      }
    },
    flush_buffered=() => {
      match buffer.flush() {
        Some(payload) => {
          payloads.push(payload)
          { events: [], consumed_event: true, done: false }
        }
        None => SseDecodeBatch::empty(false)
      }
    },
    finish_stream=() => {
      finalizer_calls.val = finalizer_calls.val + 1
      {
        events: [
          @provider.Finish(
            usage=@provider.Usage::zero(),
            reason=@provider.Unknown(""),
          ),
        ],
        consumed_event: false,
        done: true,
      }
    },
    response=() => payloads.join(","),
    transport~,
    on_event=event => events.push(event),
  )
  assert_eq(result.value, "partial")
  assert_eq(finalizer_calls.val, 1)
  assert_true(events.length() == 2)
  assert_true(events[0] is @provider.StreamStart)
  assert_true(events[1] is @provider.Finish(..))
  assert_true(stream.closed.val)
}

///|
async test "SSE transport does not run the protocol finalizer on idle timeout" {
  let stream = MockHttpStreamResponse::new(
    ["data: late"],
    headers={ "content-type": "text/event-stream" },
    delays_ms=[50],
  )
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}"),
    stream,
  )
  let finalizer_calls = Ref(0)
  try
    post_json_sse_events(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers=Map([]),
      body={ "stream": true },
      idle_timeout_ms=1,
      retry_policy=@provider.RetryPolicy::none(),
      start_events=[@provider.StreamStart],
      is_stream_error=event => event is @provider.StreamError(_),
      feed_line=_ => SseDecodeBatch::empty(false),
      flush_buffered=() => SseDecodeBatch::empty(false),
      finish_stream=() => {
        finalizer_calls.val = finalizer_calls.val + 1
        SseDecodeBatch::empty(true)
      },
      response=() => (),
      transport~,
      on_event=_ => (),
    )
    |> ignore
  catch {
    @provider.APICallError(message~, status_code=None, is_retryable=true, ..) =>
      assert_true(message.contains("stream idle"))
    error => fail("unexpected SSE idle timeout error: \{error}")
  } noraise {
    _ => fail("expected an SSE idle timeout error")
  }
  assert_eq(finalizer_calls.val, 0)
  assert_true(stream.closed.val)
}

///|
async test "generic SSE transport emits the V4 start envelope once" {
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
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  let decode_payload : (String) -> SseDecodeBatch[
    @provider.LanguageModelV4StreamPart,
  ] = payload => {
    if payload == "[DONE]" {
      SseDecodeBatch::empty(true)
    } else {
      payloads.push(payload)
      {
        events: [@provider.V4Raw(Json::string(payload))],
        consumed_event: true,
        done: false,
      }
    }
  }
  let warnings = [@provider.Other(message="mock warning")]
  let result = post_json_sse_events(
    provider_name="mock",
    url="https://example.test/v1/stream",
    headers=Map([]),
    body={ "stream": true },
    retry_policy=@provider.RetryPolicy::none(),
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => {
      match buffer.feed_line(raw) {
        Some(payload) => decode_payload(payload)
        None => SseDecodeBatch::empty(false)
      }
    },
    flush_buffered=() => {
      match buffer.flush() {
        Some(payload) => decode_payload(payload)
        None => SseDecodeBatch::empty(false)
      }
    },
    response=() => payloads.join(","),
    transport~,
    on_event=event => events.push(event),
  )
  assert_eq(result.value, "first,second")
  assert_eq(events.length(), 3)
  match events[0] {
    @provider.V4StreamStart(warnings~) =>
      assert_eq(warnings, [@provider.Other(message="mock warning")])
    _ => fail("expected V4 stream start")
  }
  assert_true(events[1] is @provider.V4Raw(String("first")))
  assert_true(events[2] is @provider.V4Raw(String("second")))
}

///|
async test "SSE start policy buffers accepted frames until provider output" {
  let stream = MockHttpStreamResponse::new(
    ["data: accepted", "", "data: output", "", "data: [DONE]", ""],
    headers={ "content-type": "text/event-stream" },
  )
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}"),
    stream,
  )
  let buffer = EventSourceBuffer::new()
  let accepted = Ref(false)
  let output = Ref(false)
  let started_count = Ref(0)
  let events : Array[@provider.StreamEvent] = []
  let decode_payload = payload => {
    if payload == "[DONE]" {
      SseDecodeBatch::empty(true)
    } else {
      if payload == "accepted" {
        accepted.val = true
      } else if payload == "output" {
        output.val = true
      }
      {
        events: [@provider.Raw(Json::string(payload))],
        consumed_event: true,
        done: false,
      }
    }
  }
  let start_policy = SseStreamStartPolicy::new(
    is_accepted=() => accepted.val,
    is_output=() => output.val,
    on_started=() => started_count.val = started_count.val + 1,
  )
  ignore(
    post_json_sse_events(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers=Map([]),
      body={ "stream": true },
      retry_policy=@provider.RetryPolicy::none(),
      start_events=[@provider.StreamStart],
      is_stream_error=event => event is @provider.StreamError(_),
      feed_line=raw => {
        match buffer.feed_line(raw) {
          Some(payload) => decode_payload(payload)
          None => SseDecodeBatch::empty(false)
        }
      },
      flush_buffered=() => {
        match buffer.flush() {
          Some(payload) => decode_payload(payload)
          None => SseDecodeBatch::empty(false)
        }
      },
      response=() => "complete",
      start_policy~,
      transport~,
      on_event=event => events.push(event),
    ),
  )
  assert_eq(started_count.val, 1)
  assert_eq(events.length(), 3)
  assert_true(events[0] is @provider.StreamStart)
  assert_true(events[1] is @provider.Raw(String("accepted")))
  assert_true(events[2] is @provider.Raw(String("output")))
}

///|
async test "SSE accepted grace resets after each parsed setup frame" {
  let stream = MockHttpStreamResponse::new(
    ["data: accepted", "", "data: accepted", "", "data: error", ""],
    headers={ "content-type": "text/event-stream" },
    delays_ms=[0, 0, 75, 0, 150, 0],
  )
  let transport = MockHttpTransport::new(
    HttpResponse::text(status_code=200, body="{}"),
    stream,
  )
  let buffer = EventSourceBuffer::new()
  let accepted = Ref(false)
  let released = Ref(false)
  let started_count = Ref(0)
  let events : Array[@provider.StreamEvent] = []
  let decode_payload : (String) -> SseDecodeBatch[@provider.StreamEvent] raise = payload => {
    if payload == "accepted" {
      accepted.val = true
      {
        events: [@provider.Raw(Json::string(payload))],
        consumed_event: true,
        done: false,
      }
    } else if payload == "error" && !released.val {
      raise @provider_utils.SseProviderError(
        message="error within reset grace window",
        status_code=500,
        response_body="error",
        is_retryable=false,
      )
    } else {
      {
        events: [
          @provider.StreamError(@provider.StreamErrorInfo::new("late error")),
        ],
        consumed_event: true,
        done: false,
      }
    }
  }
  let start_policy = SseStreamStartPolicy::new(
    is_accepted=() => accepted.val,
    is_output=() => false,
    accepted_grace_ms=200,
    on_started=() => {
      released.val = true
      started_count.val = started_count.val + 1
    },
  )
  try
    post_json_sse_events(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers=Map([]),
      body={ "stream": true },
      retry_policy=@provider.RetryPolicy::none(),
      start_events=[@provider.StreamStart],
      is_stream_error=event => event is @provider.StreamError(_),
      feed_line=raw => {
        match buffer.feed_line(raw) {
          Some(payload) => decode_payload(payload)
          None => SseDecodeBatch::empty(false)
        }
      },
      flush_buffered=() => {
        match buffer.flush() {
          Some(payload) => decode_payload(payload)
          None => SseDecodeBatch::empty(false)
        }
      },
      response=() => "unreachable",
      start_policy~,
      transport~,
      on_event=event => events.push(event),
    )
    |> ignore
  catch {
    @provider.APICallError(message="error within reset grace window", ..) => ()
    error => fail("unexpected reset-grace error: \{error}")
  } noraise {
    _ => fail("expected the error to remain inside the reset grace window")
  }
  assert_eq(started_count.val, 0)
  assert_eq(events.length(), 0)
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
  let events : Array[@provider.StreamEvent] = []
  try
    post_json_sse_events(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers={ "Authorization": "Bearer stream-key" },
      body={ "stream": true, "prompt": "hello" },
      retry_policy=@provider.RetryPolicy::none(),
      start_events=[@provider.StreamStart],
      is_stream_error=event => event is @provider.StreamError(_),
      feed_line=_raw => {
        raise @provider_utils.SseProviderError(
          message="quota exceeded",
          status_code=429,
          response_body="{\"type\":\"insufficient_quota\"}",
          is_retryable=true,
        )
      },
      flush_buffered=() => SseDecodeBatch::empty(false),
      response=() => "unreachable",
      transport~,
      on_event=event => events.push(event),
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
      is_retryable~,
      ..
    ) => {
      assert_eq(message, "quota exceeded")
      assert_eq(url, "https://example.test/v1/stream")
      assert_true(request_body.contains("\"prompt\":\"hello\""))
      assert_eq(request_headers["Authorization"], "Bearer stream-key")
      assert_eq(status_code, Some(429))
      assert_eq(response_headers["x-request-id"], "sse-error-1")
      assert_true(response_body.contains("insufficient_quota"))
      assert_eq(is_retryable, true)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed SSE provider error")
  }
  assert_eq(events.length(), 0)
  assert_true(stream.closed.val)
}

///|
priv struct AlwaysFailingHttpTransport {
  buffered_calls : Ref[Int]
  stream_calls : Ref[Int]
}

///|
fn AlwaysFailingHttpTransport::new() -> AlwaysFailingHttpTransport {
  { buffered_calls: Ref(0), stream_calls: Ref(0) }
}

///|
impl HttpTransport for AlwaysFailingHttpTransport with fn fetch(self, _request) {
  self.buffered_calls.val = self.buffered_calls.val + 1
  fail("dial refused")
}

///|
impl HttpTransport for AlwaysFailingHttpTransport with fn fetch_stream(
  self,
  _request,
) {
  self.stream_calls.val = self.stream_calls.val + 1
  fail("stream dial refused")
}

///|
priv struct SlowHttpTransport {}

///|
impl HttpTransport for SlowHttpTransport with fn fetch(_self, _request) {
  @async.sleep(50)
  HttpResponse::text(status_code=200, body="{}")
}

///|
impl HttpTransport for SlowHttpTransport with fn fetch_stream(_self, _request) {
  fail("unused slow stream transport")
}

///|
priv struct ExistingApiCallErrorTransport {}

///|
impl HttpTransport for ExistingApiCallErrorTransport with fn fetch(
  _self,
  _request,
) {
  raise @provider.APICallError(
    message="existing API call error",
    url="https://existing.test/error",
    request_body="existing request",
    request_headers=Map([]),
    status_code=Some(418),
    response_headers={ "x-existing": "true" },
    response_body="existing response",
    is_retryable=false,
    data=None,
    cause=Some("existing cause"),
  )
}

///|
impl HttpTransport for ExistingApiCallErrorTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("unused existing-error stream transport")
}

///|
priv struct ReadFailingStreamResponse {
  closed : Ref[Bool]
}

///|
impl HttpStreamResponse for ReadFailingStreamResponse with fn status_code(_self) {
  200
}

///|
impl HttpStreamResponse for ReadFailingStreamResponse with fn reason(_self) {
  "OK"
}

///|
impl HttpStreamResponse for ReadFailingStreamResponse with fn headers(_self) {
  { "content-type": "text/event-stream" }
}

///|
impl HttpStreamResponse for ReadFailingStreamResponse with fn read_until(
  _self,
  _separator,
) {
  fail("stream read reset")
}

///|
impl HttpStreamResponse for ReadFailingStreamResponse with fn read_all(_self) {
  b""
}

///|
impl HttpStreamResponse for ReadFailingStreamResponse with fn close(self) {
  self.closed.val = true
}

///|
priv struct ReadFailingHttpTransport {
  stream : ReadFailingStreamResponse
}

///|
impl HttpTransport for ReadFailingHttpTransport with fn fetch(_self, _request) {
  fail("unused buffered transport")
}

///|
impl HttpTransport for ReadFailingHttpTransport with fn fetch_stream(
  self,
  _request,
) {
  self.stream as &HttpStreamResponse
}

///|
async test "buffered transport failures retry then become API call errors" {
  let transport = AlwaysFailingHttpTransport::new()
  let retry_policy = @provider.RetryPolicy::new(
    max_retries=2,
    initial_delay_ms=0,
    max_delay_ms=0,
  )
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers={ "Authorization": "Bearer network-key" },
      body={ "prompt": "hello" },
      retry_policy~,
      transport~,
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
      is_retryable~,
      data~,
      cause~
    ) => {
      assert_true(message.contains("Cannot connect to API"))
      assert_true(message.contains("dial refused"))
      assert_eq(url, "https://example.test/v1/generate")
      assert_true(request_body.contains("\"prompt\":\"hello\""))
      assert_eq(request_headers["Authorization"], "Bearer network-key")
      assert_eq(status_code, None)
      assert_eq(response_headers.length(), 0)
      assert_eq(response_body, "")
      assert_true(is_retryable)
      assert_eq(data, None)
      assert_true(cause.unwrap_or("").contains("dial refused"))
    }
    error => fail("unexpected buffered transport error: \{error}")
  } noraise {
    _ => fail("expected a buffered transport error")
  }
  assert_eq(transport.buffered_calls.val, 3)
}

///|
async test "binary multipart and GET share the API call error boundary" {
  let transport = AlwaysFailingHttpTransport::new()
  try
    post_json_binary(
      provider_name="mock",
      url="https://example.test/v1/binary",
      headers=Map([]),
      body={ "input": "binary" },
      retry_policy=@provider.RetryPolicy::none(),
      transport~,
    )
    |> ignore
  catch {
    @provider.APICallError(status_code=None, request_body~, ..) =>
      assert_true(request_body.contains("binary"))
    error => fail("unexpected binary transport error: \{error}")
  } noraise {
    _ => fail("expected a binary transport error")
  }
  let form_data = encode_multipart_form_data([
    MultipartField::text(name="prompt", value="multipart"),
  ])
  try
    post_multipart(
      provider_name="mock",
      url="https://example.test/v1/multipart",
      headers={ "X-Test": "multipart" },
      form_data~,
      retry_policy=@provider.RetryPolicy::none(),
      transport~,
    )
    |> ignore
  catch {
    @provider.APICallError(
      status_code=None,
      request_body~,
      request_headers~,
      ..
    ) => {
      assert_true(request_body.contains("multipart"))
      assert_true(
        request_headers["Content-Type"].contains("multipart/form-data"),
      )
    }
    error => fail("unexpected multipart transport error: \{error}")
  } noraise {
    _ => fail("expected a multipart transport error")
  }
  try
    get_json(
      provider_name="mock",
      url="https://example.test/v1/status",
      headers={ "X-Test": "get" },
      retry_policy=@provider.RetryPolicy::none(),
      transport~,
    )
    |> ignore
  catch {
    @provider.APICallError(status_code=None, request_body="", url~, ..) =>
      assert_eq(url, "https://example.test/v1/status")
    error => fail("unexpected GET transport error: \{error}")
  } noraise {
    _ => fail("expected a GET transport error")
  }
  assert_eq(transport.buffered_calls.val, 3)
}

///|
async test "SSE connection failures retry then become API call errors" {
  let transport = AlwaysFailingHttpTransport::new()
  let retry_policy = @provider.RetryPolicy::new(
    max_retries=1,
    initial_delay_ms=0,
    max_delay_ms=0,
  )
  let events : Array[@provider.StreamEvent] = []
  try
    post_json_sse_events(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers={ "Authorization": "Bearer stream-key" },
      body={ "stream": true },
      retry_policy~,
      start_events=[@provider.StreamStart],
      is_stream_error=event => event is @provider.StreamError(_),
      feed_line=_ => SseDecodeBatch::empty(false),
      flush_buffered=() => SseDecodeBatch::empty(false),
      response=() => "unreachable",
      transport~,
      on_event=event => events.push(event),
    )
    |> ignore
  catch {
    @provider.APICallError(
      message~,
      status_code=None,
      request_body~,
      is_retryable=true,
      ..
    ) => {
      assert_true(message.contains("stream dial refused"))
      assert_true(request_body.contains("\"stream\":true"))
    }
    error => fail("unexpected SSE transport error: \{error}")
  } noraise {
    _ => fail("expected an SSE transport error")
  }
  assert_eq(transport.stream_calls.val, 2)
  assert_eq(events.length(), 0)
}

///|
async test "SSE read failures become API call errors" {
  let stream = ReadFailingStreamResponse::{ closed: Ref(false) }
  let transport = ReadFailingHttpTransport::{ stream, }
  try
    post_json_sse_events(
      provider_name="mock",
      url="https://example.test/v1/stream",
      headers=Map([]),
      body={ "stream": true },
      retry_policy=@provider.RetryPolicy::none(),
      start_events=[@provider.StreamStart],
      is_stream_error=event => event is @provider.StreamError(_),
      feed_line=_ => SseDecodeBatch::empty(false),
      flush_buffered=() => SseDecodeBatch::empty(false),
      response=() => "unreachable",
      transport~,
      on_event=_ => (),
    )
    |> ignore
  catch {
    @provider.APICallError(message~, status_code=None, is_retryable=true, ..) =>
      assert_true(message.contains("stream read reset"))
    error => fail("unexpected SSE read error: \{error}")
  } noraise {
    _ => fail("expected an SSE read error")
  }
  assert_true(stream.closed.val)
}

///|
async test "buffered timeout has no HTTP status" {
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/slow",
      headers=Map([]),
      body=Json::empty_object(),
      timeout_ms=1,
      retry_policy=@provider.RetryPolicy::none(),
      transport=SlowHttpTransport::{  },
    )
    |> ignore
  catch {
    @provider.APICallError(
      message~,
      status_code=None,
      is_retryable=true,
      cause~,
      ..
    ) => {
      assert_true(message.contains("timed out"))
      assert_true(cause.unwrap_or("").contains("timed out"))
    }
    error => fail("unexpected timeout error: \{error}")
  } noraise {
    _ => fail("expected a timeout error")
  }
}

///|
async test "transport preserves an existing API call error" {
  try
    post_json(
      provider_name="mock",
      url="https://example.test/v1/generate",
      headers=Map([]),
      body=Json::empty_object(),
      retry_policy=@provider.RetryPolicy::none(),
      transport=ExistingApiCallErrorTransport::{  },
    )
    |> ignore
  catch {
    @provider.APICallError(
      message="existing API call error",
      url="https://existing.test/error",
      status_code=Some(418),
      response_body="existing response",
      cause=Some("existing cause"),
      ..
    ) => ()
    error => fail("unexpected existing API call error: \{error}")
  } noraise {
    _ => fail("expected the existing API call error")
  }
}

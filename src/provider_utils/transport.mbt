///|
/// Successful SSE response together with transport diagnostics.
pub(all) struct SseHttpResponse[T] {
  value : T
  request : @provider.RequestMetadata
  response : @provider.ResponseMetadata
} derive(Debug)

///|
suberror SseTransportError {
  SseTransportError(String, String)
} derive(Debug)

///|
suberror SseTimeoutError {
  SseTimeoutError(String, String)
} derive(Debug)

///|
suberror SseProtocolError {
  SseProtocolError(String, String)
} derive(Debug)

///|
/// A provider error frame carried inside an otherwise successful SSE HTTP
/// response. The transport converts it to `APICallError` while it still owns
/// the request and response diagnostics.
pub(all) suberror SseProviderError {
  SseProviderError(
    message~ : String,
    status_code~ : Int,
    response_body~ : String,
    is_retryable~ : Bool
  )
} derive(Debug)

///|
fn is_retryable_sse_error(error : Error) -> Bool {
  match error {
    @provider.APICallError(is_retryable~, ..) => is_retryable
    SseTransportError(_, _) | SseTimeoutError(_, _) => true
    _ => false
  }
}

///|
fn decode_sse_batch(
  decode : () -> DecodeBatch raise,
  url : String,
  request_body : String,
  request_headers : Map[String, String],
  response_headers : Map[String, String],
) -> DecodeBatch raise {
  decode() catch {
    SseProviderError(message~, status_code~, response_body~, is_retryable~) =>
      raise @provider.APICallError(
        message~,
        url~,
        request_body~,
        request_headers=copy_headers(request_headers),
        status_code~,
        response_headers~,
        response_body~,
        is_retryable~,
      )
    error => raise error
  }
}

///|
async fn emit_batch(
  batch : DecodeBatch,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> Unit {
  for event in batch.events {
    on_event(event)
  }
}

///|
async fn read_stream_line(
  reader : &HttpStreamResponse,
  idle_timeout_ms : Int,
) -> String?? {
  if idle_timeout_ms <= 0 {
    Some(reader.read_until("\n"))
  } else {
    @async.with_timeout_opt(idle_timeout_ms, () => reader.read_until("\n"))
  }
}

///|
async fn[T] run_sse_attempt(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  idle_timeout_ms : Int,
  expected_terminator : String,
  feed_line~ : (String) -> DecodeBatch raise,
  flush_buffered~ : () -> DecodeBatch raise,
  response~ : () -> T,
  warnings : Array[@provider.Warning],
  cancellation_token : @provider.CancellationToken?,
  error_to_message : ((Json) -> String?)?,
  is_retryable_response : ((Int, Json?) -> Bool?)?,
  emitted : Ref[Bool],
  transport : &HttpTransport,
  on_event~ : async (@provider.StreamEvent) -> Unit,
) -> SseHttpResponse[T] {
  @provider.check_cancellation(cancellation_token)
  let request_body = body.stringify()
  let fetch_stream = () => {
    transport.fetch_stream(
      HttpRequest::post(url~, headers~, body=@utf8.encode(request_body)),
    ) catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error => raise SseTransportError(provider_name, @debug.to_string(error))
    }
  }
  let stream_option = if idle_timeout_ms <= 0 {
    Some(fetch_stream())
  } else {
    @async.with_timeout_opt(idle_timeout_ms, fetch_stream)
  }
  let stream = match stream_option {
    Some(value) => value
    None =>
      raise SseTimeoutError(
        provider_name,
        "response headers timed out after " + idle_timeout_ms.to_string() + "ms",
      )
  }
  defer stream.close()
  guard stream.status_code() >= 200 && stream.status_code() < 300 else {
    let error_body = @utf8.decode(stream.read_all()) catch { _ => "" }
    let error_json : Json? = try @json.parse(error_body) catch {
      _ => None
    } noraise {
      value => Some(value)
    }
    let message = match (error_to_message, error_json) {
      (Some(extract), Some(value)) => extract(value).unwrap_or(error_body)
      _ => error_body
    }
    let retryable = match is_retryable_response {
      Some(resolve) =>
        resolve(stream.status_code(), error_json).unwrap_or(
          is_retryable_status(stream.status_code()),
        )
      None => is_retryable_status(stream.status_code())
    }
    raise @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers=copy_headers(headers),
      status_code=stream.status_code(),
      response_headers=stream.headers(),
      response_body=error_body,
      is_retryable=retryable,
    )
  }
  let response_metadata = @provider.ResponseMetadata::new(
    status_code=stream.status_code(),
    headers=stream.headers(),
  )
  emitted.val = true
  on_event(@provider.StreamStart)
  for warning in warnings {
    on_event(@provider.Warning(warning))
  }
  for ;; {
    @provider.check_cancellation(cancellation_token)
    match read_stream_line(stream, idle_timeout_ms) {
      Some(Some(raw)) => {
        let batch = decode_sse_batch(
          () => feed_line(raw),
          url,
          request_body,
          headers,
          stream.headers(),
        )
        emit_batch(batch, on_event)
        if batch.done {
          return {
            value: response(),
            request: @provider.RequestMetadata::new(
              url~,
              headers~,
              body=request_body,
            ),
            response: response_metadata,
          }
        }
      }
      Some(None) => {
        let batch = decode_sse_batch(
          flush_buffered,
          url,
          request_body,
          headers,
          stream.headers(),
        )
        emit_batch(batch, on_event)
        if batch.done {
          return {
            value: response(),
            request: @provider.RequestMetadata::new(
              url~,
              headers~,
              body=request_body,
            ),
            response: response_metadata,
          }
        }
        raise SseProtocolError(
          provider_name,
          "stream ended before " + expected_terminator,
        )
      }
      None => {
        let batch = decode_sse_batch(
          flush_buffered,
          url,
          request_body,
          headers,
          stream.headers(),
        )
        emit_batch(batch, on_event)
        if batch.done {
          return {
            value: response(),
            request: @provider.RequestMetadata::new(
              url~,
              headers~,
              body=request_body,
            ),
            response: response_metadata,
          }
        }
        raise SseTimeoutError(
          provider_name,
          "stream idle for " + idle_timeout_ms.to_string() + "ms",
        )
      }
    }
  }
}

///|
/// POST a JSON request and drive a provider-specific decoder from its SSE
/// response. Retries are limited to failures before any stream event is
/// delivered, preventing duplicate text or tool-call events.
pub async fn[T] post_json_sse(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  idle_timeout_ms? : Int = 120_000,
  expected_terminator? : String = "stream terminator",
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  error_to_message? : (Json) -> String?,
  is_retryable_response? : (Int, Json?) -> Bool?,
  warnings? : Array[@provider.Warning] = [],
  feed_line~ : (String) -> DecodeBatch raise,
  flush_buffered~ : () -> DecodeBatch raise,
  response~ : () -> T,
  transport? : &HttpTransport,
  on_event~ : async (@provider.StreamEvent) -> Unit,
) -> SseHttpResponse[T] {
  let resolved_transport = transport.unwrap_or(native_http_transport())
  let mut retry_number = 0
  let mut delay = initial_retry_delay(retry_policy)
  let emitted = Ref(false)
  for ;; {
    @provider.check_cancellation(cancellation_token)
    try
      run_sse_attempt(
        provider_name~,
        url~,
        headers~,
        body~,
        idle_timeout_ms,
        expected_terminator,
        feed_line~,
        flush_buffered~,
        response~,
        warnings,
        cancellation_token,
        error_to_message,
        is_retryable_response,
        emitted,
        resolved_transport,
        on_event~,
      )
    catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error if !emitted.val &&
        is_retryable_sse_error(error) &&
        retry_policy.can_retry(retry_number) => {
        retry_number = retry_number + 1
        if delay > 0 {
          sleep_with_cancellation(delay, cancellation_token)
        }
        delay = next_retry_delay(retry_policy, delay)
        continue
      }
      error => raise error
    } noraise {
      result => return result
    }
  }
}

///|
/// Successful SSE response together with transport diagnostics.
pub(all) struct SseHttpResponse[T] {
  value : T
  request : @moonai.RequestMetadata
  response : @moonai.ResponseMetadata
} derive(Debug)

///|
suberror SseStatusError {
  SseStatusError(String, Int, String)
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
fn is_retryable(error : Error) -> Bool {
  match error {
    SseStatusError(_, status_code, _) =>
      @provider_utils.is_retryable_status(status_code)
    SseTransportError(_, _) | SseTimeoutError(_, _) => true
    _ => false
  }
}

///|
async fn emit_batch(
  batch : DecodeBatch,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> Unit {
  for event in batch.events {
    on_event(event)
  }
}

///|
async fn read_stream_line(
  reader : @http.Client,
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
  warnings : Array[@moonai.Warning],
  cancellation_token : @moonai.CancellationToken?,
  emitted : Ref[Bool],
  on_event~ : async (@moonai.StreamEvent) -> Unit,
) -> SseHttpResponse[T] {
  @moonai.check_cancellation(cancellation_token)
  let client = @http.post_stream(url, headers~) catch {
    error if @async.is_cancellation_error(error) || @async.is_being_cancelled() =>
      raise error
    error => raise SseTransportError(provider_name, @debug.to_string(error))
  }
  defer client.close()
  let request_body = body.stringify()
  client.write(request_body) catch {
    error if @async.is_cancellation_error(error) || @async.is_being_cancelled() =>
      raise error
    error => raise SseTransportError(provider_name, @debug.to_string(error))
  }
  let response_option = if idle_timeout_ms <= 0 {
    Some(client.end_request())
  } else {
    @async.with_timeout_opt(idle_timeout_ms, () => client.end_request())
  }
  let http_response = match response_option {
    Some(value) => value
    None =>
      raise SseTimeoutError(
        provider_name,
        "response headers timed out after " + idle_timeout_ms.to_string() + "ms",
      )
  }
  guard http_response.code >= 200 && http_response.code < 300 else {
    let error_body = client.read_all().text() catch { _ => "" }
    raise SseStatusError(provider_name, http_response.code, error_body)
  }
  let response_metadata = @moonai.ResponseMetadata::new(
    status_code=http_response.code,
    headers=http_response.headers,
  )
  emitted.val = true
  on_event(@moonai.StreamStart)
  for warning in warnings {
    on_event(@moonai.Warning(warning))
  }
  for ;; {
    @moonai.check_cancellation(cancellation_token)
    match read_stream_line(client, idle_timeout_ms) {
      Some(Some(raw)) => {
        let batch = feed_line(raw)
        emit_batch(batch, on_event)
        if batch.done {
          return {
            value: response(),
            request: @moonai.RequestMetadata::new(
              url~,
              headers~,
              body=request_body,
            ),
            response: response_metadata,
          }
        }
      }
      Some(None) => {
        let batch = flush_buffered()
        emit_batch(batch, on_event)
        if batch.done {
          return {
            value: response(),
            request: @moonai.RequestMetadata::new(
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
        let batch = flush_buffered()
        emit_batch(batch, on_event)
        if batch.done {
          return {
            value: response(),
            request: @moonai.RequestMetadata::new(
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
  retry_policy? : @moonai.RetryPolicy = @moonai.RetryPolicy::standard(),
  cancellation_token? : @moonai.CancellationToken,
  warnings? : Array[@moonai.Warning] = [],
  feed_line~ : (String) -> DecodeBatch raise,
  flush_buffered~ : () -> DecodeBatch raise,
  response~ : () -> T,
  on_event~ : async (@moonai.StreamEvent) -> Unit,
) -> SseHttpResponse[T] {
  let mut retry_number = 0
  let mut delay = @provider_utils.initial_retry_delay(retry_policy)
  let emitted = Ref(false)
  for ;; {
    @moonai.check_cancellation(cancellation_token)
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
        emitted,
        on_event~,
      )
    catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error if !emitted.val &&
        is_retryable(error) &&
        retry_policy.can_retry(retry_number) => {
        retry_number = retry_number + 1
        if delay > 0 {
          @provider_utils.sleep_with_cancellation(delay, cancellation_token)
        }
        delay = @provider_utils.next_retry_delay(retry_policy, delay)
        continue
      }
      error => raise error
    } noraise {
      result => return result
    }
  }
}

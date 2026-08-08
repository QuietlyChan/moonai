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
fn[E] decode_sse_batch(
  decode : () -> SseDecodeBatch[E] raise,
  url : String,
  request_body : String,
  request_headers : Map[String, String],
  response_headers : Map[String, String],
) -> SseDecodeBatch[E] raise {
  decode() catch {
    SseProviderError(message~, status_code~, response_body~, is_retryable~) =>
      raise @provider.APICallError(
        message~,
        url~,
        request_body~,
        request_headers=copy_headers(request_headers),
        status_code=Some(status_code),
        response_headers~,
        response_body~,
        is_retryable~,
        data=None,
        cause=None,
      )
    error => raise error
  }
}

///|
async fn[E] emit_batch(
  batch : SseDecodeBatch[E],
  on_event : async (E) -> Unit,
) -> Unit {
  for event in batch.events {
    on_event(event)
  }
}

///|
fn[E] sse_batch_has_stream_error(
  batch : SseDecodeBatch[E],
  is_stream_error : (E) -> Bool,
) -> Bool {
  batch.events.any(is_stream_error)
}

///|
async fn[E] ensure_sse_started(
  started : Ref[Bool],
  emitted : Ref[Bool],
  start_events : Array[E],
  on_event : async (E) -> Unit,
) -> Unit {
  if !started.val {
    started.val = true
    emitted.val = true
    for event in start_events {
      on_event(event)
    }
  }
}

///|
async fn[E] start_sse_with_pending_events(
  started : Ref[Bool],
  emitted : Ref[Bool],
  waiting_after_acceptance : Ref[Bool],
  pending_events : Array[E],
  start_events : Array[E],
  start_policy : SseStreamStartPolicy?,
  on_event : async (E) -> Unit,
) -> Unit {
  guard !started.val else { return }
  if start_policy is Some(policy) {
    policy.started()
  }
  ensure_sse_started(started, emitted, start_events, on_event)
  waiting_after_acceptance.val = false
  for event in pending_events {
    on_event(event)
  }
  pending_events.clear()
}

///|
async fn[E] process_sse_batch(
  batch : SseDecodeBatch[E],
  started : Ref[Bool],
  emitted : Ref[Bool],
  waiting_after_acceptance : Ref[Bool],
  pending_events : Array[E],
  start_events : Array[E],
  is_stream_error : (E) -> Bool,
  start_policy : SseStreamStartPolicy?,
  on_event : async (E) -> Unit,
) -> Unit {
  match start_policy {
    None => {
      if batch.consumed_event || batch.done {
        ensure_sse_started(started, emitted, start_events, on_event)
      }
      emit_batch(batch, on_event)
    }
    Some(_) if started.val => emit_batch(batch, on_event)
    Some(policy) => {
      for event in batch.events {
        pending_events.push(event)
      }
      if batch.done ||
        policy.output() ||
        sse_batch_has_stream_error(batch, is_stream_error) {
        start_sse_with_pending_events(
          started, emitted, waiting_after_acceptance, pending_events, start_events,
          start_policy, on_event,
        )
      } else if policy.accepted() {
        if policy.accepted_grace_ms == 0 {
          start_sse_with_pending_events(
            started, emitted, waiting_after_acceptance, pending_events, start_events,
            start_policy, on_event,
          )
        } else {
          waiting_after_acceptance.val = true
        }
      }
    }
  }
}

///|
async fn[E] process_sse_batch_synchronized(
  state_mutex : @async.Mutex,
  batch : SseDecodeBatch[E],
  started : Ref[Bool],
  emitted : Ref[Bool],
  waiting_after_acceptance : Ref[Bool],
  pending_events : Array[E],
  start_events : Array[E],
  is_stream_error : (E) -> Bool,
  start_policy : SseStreamStartPolicy?,
  on_event : async (E) -> Unit,
) -> Unit {
  state_mutex.acquire()
  defer state_mutex.release()
  process_sse_batch(
    batch, started, emitted, waiting_after_acceptance, pending_events, start_events,
    is_stream_error, start_policy, on_event,
  )
}

///|
async fn[E] start_waiting_sse_synchronized(
  state_mutex : @async.Mutex,
  started : Ref[Bool],
  emitted : Ref[Bool],
  waiting_after_acceptance : Ref[Bool],
  pending_events : Array[E],
  start_events : Array[E],
  start_policy : SseStreamStartPolicy?,
  on_event : async (E) -> Unit,
) -> Unit {
  state_mutex.acquire()
  defer state_mutex.release()
  if waiting_after_acceptance.val && !started.val {
    start_sse_with_pending_events(
      started, emitted, waiting_after_acceptance, pending_events, start_events, start_policy,
      on_event,
    )
  }
}

///|
async fn read_stream_line(
  reader : &HttpStreamResponse,
  idle_timeout_ms : Int,
  provider_name : String,
) -> String?? {
  let read = () => {
    reader.read_until("\n") catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error =>
        match error {
          @provider.CancellationError | @provider.APICallError(..) =>
            raise error
          _ => raise SseTransportError(provider_name, @debug.to_string(error))
        }
    }
  }
  if idle_timeout_ms <= 0 {
    Some(read())
  } else {
    @async.with_timeout_opt(idle_timeout_ms, read)
  }
}

///|
async fn[E, T] run_sse_attempt(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  idle_timeout_ms : Int,
  expected_terminator : String,
  feed_line~ : (String) -> SseDecodeBatch[E] raise,
  flush_buffered~ : () -> SseDecodeBatch[E] raise,
  finish_stream : (() -> SseDecodeBatch[E] raise)?,
  response~ : () -> T,
  start_events : Array[E],
  is_stream_error : (E) -> Bool,
  cancellation_token : @provider.CancellationToken?,
  error_to_message : ((Json) -> String? raise)?,
  is_retryable_response : ((Int, Json?) -> Bool? raise)?,
  emitted : Ref[Bool],
  start_policy : SseStreamStartPolicy?,
  transport : &HttpTransport,
  on_event~ : async (E) -> Unit,
) -> SseHttpResponse[T] {
  @provider.check_cancellation(cancellation_token)
  let request_body = body.stringify()
  let fetch_stream = () => {
    transport.fetch_stream(
      HttpRequest::post(url~, headers~, body=@utf8.encode(request_body)),
    ) catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error =>
        match error {
          @provider.CancellationError | @provider.APICallError(..) =>
            raise error
          _ => raise SseTransportError(provider_name, @debug.to_string(error))
        }
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
    let error_json = parse_json_if_valid(error_body)
    let (message, retryable) = handle_failed_response(
      url~,
      request_body~,
      request_headers=headers,
      status_code=stream.status_code(),
      response_headers=stream.headers(),
      response_body=error_body,
      error_json~,
      error_to_message,
      is_retryable_response,
    )
    raise @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers=copy_headers(headers),
      status_code=Some(stream.status_code()),
      response_headers=stream.headers(),
      response_body=error_body,
      is_retryable=retryable,
      data=error_json,
      cause=None,
    )
  }
  let response_metadata = @provider.ResponseMetadata::new(
    status_code=stream.status_code(),
    headers=stream.headers(),
  )
  @async.with_task_group() <| group => {
    let started = Ref(false)
    let waiting_after_acceptance = Ref(false)
    let pending_events : Array[E] = []
    let state_mutex = @async.Mutex::Mutex()
    let grace_timer_generation = Ref(0)
    for ;; {
      @provider.check_cancellation(cancellation_token)
      match read_stream_line(stream, idle_timeout_ms, provider_name) {
        Some(Some(raw)) => {
          let batch = decode_sse_batch(
            () => feed_line(raw),
            url,
            request_body,
            headers,
            stream.headers(),
          )
          process_sse_batch_synchronized(
            state_mutex, batch, started, emitted, waiting_after_acceptance, pending_events,
            start_events, is_stream_error, start_policy, on_event,
          )
          if batch.consumed_event &&
            waiting_after_acceptance.val &&
            start_policy is Some(policy) {
            // AI SDK restarts the accepted grace race after every parsed frame.
            grace_timer_generation.val = grace_timer_generation.val + 1
            let timer_generation = grace_timer_generation.val
            group.spawn_bg(no_wait=true) <| () => {
              @async.sleep(policy.accepted_grace_ms)
              state_mutex.acquire()
              defer state_mutex.release()
              if grace_timer_generation.val == timer_generation &&
                waiting_after_acceptance.val &&
                !started.val {
                start_sse_with_pending_events(
                  started, emitted, waiting_after_acceptance, pending_events, start_events,
                  start_policy, on_event,
                )
              }
            }
            @async.pause()
          }
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
          process_sse_batch_synchronized(
            state_mutex, batch, started, emitted, waiting_after_acceptance, pending_events,
            start_events, is_stream_error, start_policy, on_event,
          )
          if !started.val && start_policy is Some(policy) && policy.accepted() {
            start_waiting_sse_synchronized(
              state_mutex, started, emitted, waiting_after_acceptance, pending_events,
              start_events, start_policy, on_event,
            )
          }
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
          match finish_stream {
            Some(finish) => {
              // `flush_buffered` only drains the SSE framing buffer. The
              // protocol transform is finalized after a real EOF, but not
              // after an idle-timeout read (the branches are intentionally
              // separate below).
              let finish_batch = decode_sse_batch(
                finish,
                url,
                request_body,
                headers,
                stream.headers(),
              )
              process_sse_batch_synchronized(
                state_mutex, finish_batch, started, emitted, waiting_after_acceptance,
                pending_events, start_events, is_stream_error, start_policy, on_event,
              )
              if finish_batch.done {
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
            None => ()
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
          process_sse_batch_synchronized(
            state_mutex, batch, started, emitted, waiting_after_acceptance, pending_events,
            start_events, is_stream_error, start_policy, on_event,
          )
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
}

///|
/// POST JSON and drive an event-vocabulary-neutral SSE decoder.
///
/// `start_events` are emitted atomically when the request crosses the
/// stream-start boundary. This lets V4 models use one `V4StreamStart` carrying
/// all warnings, while other stream contracts can choose their own lifecycle.
pub async fn[E, T] post_json_sse_events(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  idle_timeout_ms? : Int = 120_000,
  expected_terminator? : String = "stream terminator",
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  error_to_message? : (Json) -> String? raise,
  is_retryable_response? : (Int, Json?) -> Bool? raise,
  start_events~ : Array[E],
  is_stream_error~ : (E) -> Bool,
  feed_line~ : (String) -> SseDecodeBatch[E] raise,
  flush_buffered~ : () -> SseDecodeBatch[E] raise,
  finish_stream? : () -> SseDecodeBatch[E] raise,
  response~ : () -> T,
  start_policy? : SseStreamStartPolicy,
  transport? : &HttpTransport,
  on_event~ : async (E) -> Unit,
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
        finish_stream,
        response~,
        start_events,
        is_stream_error,
        cancellation_token,
        error_to_message,
        is_retryable_response,
        emitted,
        start_policy,
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
        if start_policy is Some(policy) {
          policy.retry()
        }
        if delay > 0 {
          sleep_with_cancellation(delay, cancellation_token)
        }
        delay = next_retry_delay(retry_policy, delay)
        continue
      }
      error =>
        raise normalize_api_transport_error(
          error,
          url~,
          request_body=body.stringify(),
          request_headers=headers,
        )
    } noraise {
      result => return result
    }
  }
}

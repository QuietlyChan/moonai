///|
/// Successful JSON HTTP response together with the exact request and response
/// metadata retained by the transport layer.
pub(all) struct JsonHttpResponse {
  value : Json
  request : @moonai.RequestMetadata
  response : @moonai.ResponseMetadata
} derive(Debug)

///|
/// A non-successful provider response. It is kept typed so retry policy can
/// distinguish retryable status codes from permanent client errors.
suberror HttpStatusError {
  HttpStatusError(String, Int, String)
} derive(Debug)

///|
/// A network/connection failure which is safe to retry by default.
suberror HttpTransportError {
  HttpTransportError(String, String)
} derive(Debug)

///|
/// A provider response that exceeded its configured timeout.
suberror HttpTimeoutError {
  HttpTimeoutError(String, String)
} derive(Debug)

///|
/// A response body that could not be decoded as JSON. Protocol errors are not
/// retried because repeating the same request will not repair the body.
suberror HttpDecodeError {
  HttpDecodeError(String, String)
} derive(Debug)

///|
fn response_metadata(
  response : @http.Response,
  body : String,
  value : Json,
) -> @moonai.ResponseMetadata {
  let id = metadata_json_string_field(value, "id")
  let model_id = match metadata_json_string_field(value, "model") {
    Some(model) => Some(model)
    None => metadata_json_string_field(value, "model_id")
  }
  let created_at = match metadata_json_int_field_opt(value, "created_at") {
    Some(created) => Some(created)
    None => metadata_json_int_field_opt(value, "created")
  }
  let status_code = Some(response.code)
  let headers = copy_headers(response.headers)
  @moonai.ResponseMetadata::new(
    id?,
    model_id?,
    created_at?,
    status_code?,
    headers~,
    body~,
  )
}

// These small wrappers keep the JSON helpers private to this package while
// making the response metadata code readable in pattern-heavy transport code.

///|
fn metadata_json_string_field(json : Json, field : String) -> String? {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn metadata_json_int_field_opt(json : Json, field : String) -> Int? {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(Number(value, ..)) => Some(value.to_int())
        _ => None
      }
    _ => None
  }
}

///|
fn is_retryable(error : Error) -> Bool {
  match error {
    HttpStatusError(_, status_code, _) => is_retryable_status(status_code)
    HttpTransportError(_, _) | HttpTimeoutError(_, _) => true
    _ => false
  }
}

///|
async fn post_json_once(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  timeout_ms : Int,
  cancellation_token : @moonai.CancellationToken?,
) -> JsonHttpResponse {
  @moonai.check_cancellation(cancellation_token)
  let result = if timeout_ms <= 0 {
    @http.post(url, body, headers~) catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error => raise HttpTransportError(provider_name, @debug.to_string(error))
    }
  } else {
    match
      @async.with_timeout_opt(timeout_ms, () => {
        @http.post(url, body, headers~) catch {
          error if @async.is_cancellation_error(error) ||
            @async.is_being_cancelled() => raise error
          error =>
            raise HttpTransportError(provider_name, @debug.to_string(error))
        }
      }) {
      Some(value) => value
      None =>
        raise HttpTimeoutError(
          provider_name,
          "request timed out after " + timeout_ms.to_string() + "ms",
        )
    }
  }
  let (response, response_data) = result
  let response_body = response_data.text()
  guard response.code >= 200 && response.code < 300 else {
    raise HttpStatusError(provider_name, response.code, response_body)
  }
  let value = @json.parse(response_body) catch {
    error =>
      raise HttpDecodeError(
        provider_name,
        @debug.to_string(error) + "; body: " + response_body,
      )
  }
  {
    value,
    request: @moonai.RequestMetadata::new(
      url~,
      headers=copy_headers(headers),
      body=body.stringify(),
    ),
    response: response_metadata(response, response_body, value),
  }
}

///|
/// POST a JSON request and parse a successful JSON response. Retryable network
/// and provider failures are retried according to `retry_policy`.
pub async fn post_json(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  timeout_ms? : Int = 120_000,
  retry_policy? : @moonai.RetryPolicy = @moonai.RetryPolicy::standard(),
  cancellation_token? : @moonai.CancellationToken,
) -> JsonHttpResponse {
  let mut retry_number = 0
  let mut delay = initial_retry_delay(retry_policy)
  for ;; {
    @moonai.check_cancellation(cancellation_token)
    try
      post_json_once(
        provider_name~,
        url~,
        headers~,
        body~,
        timeout_ms,
        cancellation_token,
      )
    catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error if is_retryable(error) && retry_policy.can_retry(retry_number) => {
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

///|
/// Run provider-specific failed-response hooks while the transport still owns
/// the complete request and response diagnostics.
///
/// AI SDK wraps exceptions from `failedResponseHandler` in a new
/// `APICallError` instead of leaking a provider parser implementation detail.
/// Existing API call errors and cancellation keep their original identity.
fn handle_failed_response(
  url~ : String,
  request_body~ : String,
  request_headers~ : Map[String, String],
  status_code~ : Int,
  response_headers~ : Map[String, String],
  response_body~ : String,
  error_json~ : Json?,
  error_to_message : ((Json) -> String? raise)?,
  is_retryable_response : ((Int, Json?) -> Bool? raise)?,
) -> (String, Bool) raise {
  try {
    let message = match (error_to_message, error_json) {
      (Some(extract), Some(value)) => extract(value).unwrap_or(response_body)
      _ => response_body
    }
    let retryable = match is_retryable_response {
      Some(resolve) =>
        resolve(status_code, error_json).unwrap_or(
          is_retryable_status(status_code),
        )
      None => is_retryable_status(status_code)
    }
    (message, retryable)
  } catch {
    error if @async.is_cancellation_error(error) || @async.is_being_cancelled() =>
      raise error
    error =>
      match error {
        @provider.CancellationError => raise error
        @provider.APICallError(..) => raise error
        _ =>
          raise @provider.APICallError(
            message="Failed to process error response",
            url~,
            request_body~,
            request_headers=copy_headers(request_headers),
            status_code=Some(status_code),
            response_headers=copy_headers(response_headers),
            response_body~,
            is_retryable=is_retryable_status(status_code),
            data=None,
            cause=Some(@debug.to_string(error)),
          )
      }
  } noraise {
    result => result
  }
}

///|
/// Convert retry-exhausted transport failures into AI SDK's public API-call
/// error boundary. A missing status code means that no HTTP response was
/// received; response diagnostics are therefore intentionally empty.
fn normalize_api_transport_error(
  error : Error,
  url~ : String,
  request_body~ : String,
  request_headers~ : Map[String, String],
) -> Error {
  match error {
    HttpTransportError(_, cause) | SseTransportError(_, cause) =>
      @provider.APICallError(
        message="Cannot connect to API: " + cause,
        url~,
        request_body~,
        request_headers=copy_headers(request_headers),
        status_code=None,
        response_headers=Map([]),
        response_body="",
        is_retryable=true,
        data=None,
        cause=Some(cause),
      )
    HttpTimeoutError(_, message) | SseTimeoutError(_, message) =>
      @provider.APICallError(
        message~,
        url~,
        request_body~,
        request_headers=copy_headers(request_headers),
        status_code=None,
        response_headers=Map([]),
        response_body="",
        is_retryable=true,
        data=None,
        cause=Some(message),
      )
    _ => error
  }
}

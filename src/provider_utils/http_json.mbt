///|
/// Successful JSON HTTP response together with the exact request and response
/// metadata retained by the transport layer.
pub(all) struct JsonHttpResponse {
  value : Json
  request : @provider.RequestMetadata
  response : @provider.ResponseMetadata
} derive(Debug)

///|
/// Successful binary HTTP response together with transport diagnostics.
pub(all) struct BinaryHttpResponse {
  value : Bytes
  request : @provider.RequestMetadata
  response : @provider.ResponseMetadata
} derive(Debug)

///|
/// Binary resource downloaded for a multipart file field.
pub(all) struct DownloadedFile {
  data : Bytes
  media_type : String
  response : @provider.ResponseMetadata
} derive(Debug, Eq)

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
  response : HttpResponse,
  body : String,
  value : Json,
) -> @provider.ResponseMetadata {
  let id = metadata_json_string_field(value, "id")
  let model_id = match metadata_json_string_field(value, "model") {
    Some(model) => Some(model)
    None => metadata_json_string_field(value, "model_id")
  }
  let created_at = match metadata_json_int_field_opt(value, "created_at") {
    Some(created) => Some(created)
    None => metadata_json_int_field_opt(value, "created")
  }
  let status_code = Some(response.status_code)
  let headers = copy_headers(response.headers)
  @provider.ResponseMetadata::new(
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
    @provider.APICallError(is_retryable~, ..) => is_retryable
    HttpTransportError(_, _) | HttpTimeoutError(_, _) => true
    _ => false
  }
}

///|
async fn fetch_buffered_with_timeout(
  provider_name : String,
  request : HttpRequest,
  timeout_ms : Int,
  transport : &HttpTransport,
) -> HttpResponse {
  let fetch = () => {
    transport.fetch(request) catch {
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error => raise HttpTransportError(provider_name, @debug.to_string(error))
    }
  }
  if timeout_ms <= 0 {
    fetch()
  } else {
    match @async.with_timeout_opt(timeout_ms, fetch) {
      Some(value) => value
      None =>
        raise HttpTimeoutError(
          provider_name,
          "request timed out after " + timeout_ms.to_string() + "ms",
        )
    }
  }
}

///|
async fn post_data_json_once(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Bytes,
  request_body~ : String,
  timeout_ms : Int,
  cancellation_token : @provider.CancellationToken?,
  error_to_message : ((Json) -> String?)?,
  is_retryable_response : ((Int, Json?) -> Bool?)?,
  transport : &HttpTransport,
) -> JsonHttpResponse {
  @provider.check_cancellation(cancellation_token)
  let response = fetch_buffered_with_timeout(
    provider_name,
    HttpRequest::post(url~, headers~, body~),
    timeout_ms,
    transport,
  )
  let response_body = response.body_text()
  guard response.is_success() else {
    let error_json : Json? = try @json.parse(response_body) catch {
      _ => None
    } noraise {
      value => Some(value)
    }
    let message = match (error_to_message, error_json) {
      (Some(extract), Some(value)) => extract(value).unwrap_or(response_body)
      _ => response_body
    }
    let retryable = match is_retryable_response {
      Some(resolve) =>
        resolve(response.status_code, error_json).unwrap_or(
          is_retryable_status(response.status_code),
        )
      None => is_retryable_status(response.status_code)
    }
    raise @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers=copy_headers(headers),
      status_code=response.status_code,
      response_headers=copy_headers(response.headers),
      response_body~,
      is_retryable=retryable,
    )
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
    request: @provider.RequestMetadata::new(
      url~,
      headers=copy_headers(headers),
      body=request_body,
    ),
    response: response_metadata(response, response_body, value),
  }
}

///|
async fn post_json_once(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  timeout_ms : Int,
  cancellation_token : @provider.CancellationToken?,
  error_to_message : ((Json) -> String?)?,
  is_retryable_response : ((Int, Json?) -> Bool?)?,
  transport : &HttpTransport,
) -> JsonHttpResponse {
  let request_body = body.stringify()
  post_data_json_once(
    provider_name~,
    url~,
    headers~,
    body=@utf8.encode(request_body),
    request_body~,
    timeout_ms,
    cancellation_token,
    error_to_message,
    is_retryable_response,
    transport,
  )
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
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  error_to_message? : (Json) -> String?,
  is_retryable_response? : (Int, Json?) -> Bool?,
  transport? : &HttpTransport,
) -> JsonHttpResponse {
  let resolved_transport = transport.unwrap_or(native_http_transport())
  let mut retry_number = 0
  let mut delay = initial_retry_delay(retry_policy)
  for ;; {
    @provider.check_cancellation(cancellation_token)
    try
      post_json_once(
        provider_name~,
        url~,
        headers~,
        body~,
        timeout_ms,
        cancellation_token,
        error_to_message,
        is_retryable_response,
        resolved_transport,
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

///|
async fn post_json_binary_once(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  timeout_ms : Int,
  cancellation_token : @provider.CancellationToken?,
  error_to_message : ((Json) -> String?)?,
  is_retryable_response : ((Int, Json?) -> Bool?)?,
  transport : &HttpTransport,
) -> BinaryHttpResponse {
  @provider.check_cancellation(cancellation_token)
  let request_body = body.stringify()
  let response = fetch_buffered_with_timeout(
    provider_name,
    HttpRequest::post(url~, headers~, body=@utf8.encode(request_body)),
    timeout_ms,
    transport,
  )
  let value = response.body
  guard response.is_success() else {
    let response_body = binary_error_body(value)
    let error_json : Json? = try @json.parse(response_body) catch {
      _ => None
    } noraise {
      parsed => Some(parsed)
    }
    let message = match (error_to_message, error_json) {
      (Some(extract), Some(parsed)) => extract(parsed).unwrap_or(response_body)
      _ => response_body
    }
    let retryable = match is_retryable_response {
      Some(resolve) =>
        resolve(response.status_code, error_json).unwrap_or(
          is_retryable_status(response.status_code),
        )
      None => is_retryable_status(response.status_code)
    }
    raise @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers=copy_headers(headers),
      status_code=response.status_code,
      response_headers=copy_headers(response.headers),
      response_body~,
      is_retryable=retryable,
    )
  }
  {
    value,
    request: @provider.RequestMetadata::new(
      url~,
      headers=copy_headers(headers),
      body=request_body,
    ),
    response: @provider.ResponseMetadata::new(
      status_code=response.status_code,
      headers=copy_headers(response.headers),
    ),
  }
}

///|
/// POST JSON and retain a successful binary response without text conversion.
pub async fn post_json_binary(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  timeout_ms? : Int = 120_000,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  error_to_message? : (Json) -> String?,
  is_retryable_response? : (Int, Json?) -> Bool?,
  transport? : &HttpTransport,
) -> BinaryHttpResponse {
  let resolved_transport = transport.unwrap_or(native_http_transport())
  let mut retry_number = 0
  let mut delay = initial_retry_delay(retry_policy)
  for ;; {
    @provider.check_cancellation(cancellation_token)
    try
      post_json_binary_once(
        provider_name~,
        url~,
        headers~,
        body~,
        timeout_ms,
        cancellation_token,
        error_to_message,
        is_retryable_response,
        resolved_transport,
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
      response => return response
    }
  }
}

///|
/// POST multipart/form-data and decode a successful JSON response. Binary file
/// bytes are retained only in the wire body; request metadata uses a redacted
/// diagnostic representation with filenames, media types, and byte counts.
pub async fn post_multipart(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  form_data~ : MultipartFormData,
  timeout_ms? : Int = 120_000,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  error_to_message? : (Json) -> String?,
  is_retryable_response? : (Int, Json?) -> Bool?,
  transport? : &HttpTransport,
) -> JsonHttpResponse {
  let resolved_transport = transport.unwrap_or(native_http_transport())
  let request_headers = copy_headers(headers)
  request_headers["Content-Type"] = form_data.content_type
  let mut retry_number = 0
  let mut delay = initial_retry_delay(retry_policy)
  for ;; {
    @provider.check_cancellation(cancellation_token)
    try
      post_data_json_once(
        provider_name~,
        url~,
        headers=request_headers,
        body=form_data.body,
        request_body=form_data.diagnostic_body,
        timeout_ms,
        cancellation_token,
        error_to_message,
        is_retryable_response,
        resolved_transport,
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

///|
/// Perform one GET request and decode its JSON response.
///
/// GET is kept separate from `post_json` because providers commonly use it for
/// idempotent task polling. It shares the same typed transport errors,
/// retry-policy handling, and response metadata contract as POST requests.
async fn get_json_once(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  timeout_ms : Int,
  cancellation_token : @provider.CancellationToken?,
  error_to_message : ((Json) -> String?)?,
  is_retryable_response : ((Int, Json?) -> Bool?)?,
  transport : &HttpTransport,
) -> JsonHttpResponse {
  @provider.check_cancellation(cancellation_token)
  let response = fetch_buffered_with_timeout(
    provider_name,
    HttpRequest::get(url~, headers~),
    timeout_ms,
    transport,
  )
  let response_body = response.body_text()
  let error_json : Json? = try @json.parse(response_body) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  guard response.is_success() else {
    let message = match (error_to_message, error_json) {
      (Some(extract), Some(value)) => extract(value).unwrap_or(response_body)
      _ => response_body
    }
    let retryable = match is_retryable_response {
      Some(resolve) =>
        resolve(response.status_code, error_json).unwrap_or(
          is_retryable_status(response.status_code),
        )
      None => is_retryable_status(response.status_code)
    }
    raise @provider.APICallError(
      message~,
      url~,
      request_body="",
      request_headers=copy_headers(headers),
      status_code=response.status_code,
      response_headers=copy_headers(response.headers),
      response_body~,
      is_retryable=retryable,
    )
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
    request: @provider.RequestMetadata::new(
      url~,
      headers=copy_headers(headers),
      body="",
    ),
    response: response_metadata(response, response_body, value),
  }
}

///|
/// GET a JSON resource with the shared retry and cancellation policy.
pub async fn get_json(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  timeout_ms? : Int = 120_000,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  error_to_message? : (Json) -> String?,
  is_retryable_response? : (Int, Json?) -> Bool?,
  transport? : &HttpTransport,
) -> JsonHttpResponse {
  let resolved_transport = transport.unwrap_or(native_http_transport())
  let mut retry_number = 0
  let mut delay = initial_retry_delay(retry_policy)
  for ;; {
    @provider.check_cancellation(cancellation_token)
    try
      get_json_once(
        provider_name~,
        url~,
        headers~,
        timeout_ms,
        cancellation_token,
        error_to_message,
        is_retryable_response,
        resolved_transport,
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

///|
fn downloaded_media_type(headers : Map[String, String]) -> String {
  match headers.get("content-type") {
    Some(value) => value.split(";").to_array()[0].trim().to_owned()
    None =>
      match headers.get("Content-Type") {
        Some(value) => value.split(";").to_array()[0].trim().to_owned()
        None => "application/octet-stream"
      }
  }
}

///|
fn binary_error_body(data : Bytes) -> String {
  @utf8.decode(data) catch {
    _ => "<binary response: \{data.length()} bytes>"
  }
}

///|
async fn download_file_once(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  timeout_ms : Int,
  cancellation_token : @provider.CancellationToken?,
  transport : &HttpTransport,
) -> DownloadedFile {
  @provider.check_cancellation(cancellation_token)
  let response = fetch_buffered_with_timeout(
    provider_name,
    HttpRequest::get(url~, headers~),
    timeout_ms,
    transport,
  )
  let data = response.body
  guard response.is_success() else {
    let response_body = binary_error_body(data)
    raise @provider.APICallError(
      message=response_body,
      url~,
      request_body="",
      request_headers=copy_headers(headers),
      status_code=response.status_code,
      response_headers=copy_headers(response.headers),
      response_body~,
      is_retryable=is_retryable_status(response.status_code),
    )
  }
  let response_headers = copy_headers(response.headers)
  {
    data,
    media_type: downloaded_media_type(response_headers),
    response: @provider.ResponseMetadata::new(
      status_code=response.status_code,
      headers=response_headers,
    ),
  }
}

///|
/// Download a URL-backed file using the shared retry, timeout, and
/// cancellation policy.
pub async fn download_file(
  provider_name~ : String,
  url~ : String,
  headers? : Map[String, String] = Map([]),
  timeout_ms? : Int = 120_000,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  transport? : &HttpTransport,
) -> DownloadedFile {
  let resolved_transport = transport.unwrap_or(native_http_transport())
  let mut retry_number = 0
  let mut delay = initial_retry_delay(retry_policy)
  for ;; {
    @provider.check_cancellation(cancellation_token)
    try
      download_file_once(
        provider_name~,
        url~,
        headers~,
        timeout_ms,
        cancellation_token,
        resolved_transport,
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

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
/// Parse a successful JSON response while the transport still owns the
/// request and response diagnostics. AI SDK exposes this boundary through
/// `createJsonResponseHandler`; the callback below is its MoonBit equivalent.
fn parse_successful_json_response(
  response_body : String,
  url : String,
  request_body : String,
  request_headers : Map[String, String],
  status_code : Int,
  response_headers : Map[String, String],
) -> Json raise {
  parse_json(response_body) catch {
    @provider.JSONParseError(text~, cause~) => {
      let parse_error = @provider.JSONParseError(text~, cause~)
      raise @provider.APICallError(
        message="Invalid JSON response",
        url~,
        request_body~,
        request_headers=copy_headers(request_headers),
        status_code=Some(status_code),
        response_headers=copy_headers(response_headers),
        response_body~,
        is_retryable=false,
        data=None,
        cause=Some(parse_error.message()),
      )
    }
  }
}

///|
/// Validate a parsed successful response before it leaves the transport
/// boundary. Validation failures retain the raw parsed value as `data` and
/// are never retried, matching AI SDK's JSON response handler semantics.
fn validate_successful_json_response(
  value : Json,
  validate_response : ((Json) -> Unit raise)?,
  response_body : String,
  url : String,
  request_body : String,
  request_headers : Map[String, String],
  status_code : Int,
  response_headers : Map[String, String],
) -> Unit raise {
  guard validate_response is Some(validate) else { return }
  try validate(value) catch {
    error if @async.is_cancellation_error(error) || @async.is_being_cancelled() =>
      raise error
    error =>
      match error {
        @provider.CancellationError => raise error
        @provider.APICallError(..) => raise error
        _ =>
          raise @provider.APICallError(
            message="Invalid JSON response",
            url~,
            request_body~,
            request_headers=copy_headers(request_headers),
            status_code=Some(status_code),
            response_headers=copy_headers(response_headers),
            response_body~,
            is_retryable=false,
            data=Some(value),
            cause=Some(@debug.to_string(error)),
          )
      }
  } noraise {
    _ => ()
  }
}

///|
/// Process a parsed successful JSON response with a provider-specific handler.
/// Any handler failure other than cancellation or an existing `APICallError`
/// is wrapped while the complete HTTP diagnostics are still available. This
/// mirrors `postToApi`'s successful-response handler boundary in AI SDK.
pub fn[T] handle_json_response(
  response : JsonHttpResponse,
  handler : (Json) -> T raise,
) -> T raise {
  handler(response.value) catch {
    error if @async.is_cancellation_error(error) || @async.is_being_cancelled() =>
      raise error
    error =>
      match error {
        @provider.CancellationError => raise error
        @provider.APICallError(..) => raise error
        _ =>
          raise @provider.APICallError(
            message="Failed to process successful response",
            url=response.request.url,
            request_body=response.request.body,
            request_headers=copy_headers(response.request.headers),
            status_code=response.response.status_code,
            response_headers=copy_headers(response.response.headers),
            response_body=response.response.body.unwrap_or(
              response.value.stringify(),
            ),
            is_retryable=false,
            data=Some(response.value),
            cause=Some(@debug.to_string(error)),
          )
      }
  }
}

///|
/// Camel-case alias matching AI SDK's response-handler naming style.
pub fn[T] handleJsonResponse(
  response : JsonHttpResponse,
  handler : (Json) -> T raise,
) -> T raise {
  handle_json_response(response, handler)
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
      DownloadError(url~, message~, status_code~, status_text~) =>
        raise DownloadError(url~, message~, status_code~, status_text~)
      error if @async.is_cancellation_error(error) ||
        @async.is_being_cancelled() => raise error
      error =>
        match error {
          @provider.CancellationError | @provider.APICallError(..) =>
            raise error
          _ => raise HttpTransportError(provider_name, @debug.to_string(error))
        }
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
  error_to_message : ((Json) -> String? raise)?,
  is_retryable_response : ((Int, Json?) -> Bool? raise)?,
  validate_response : ((Json) -> Unit raise)?,
  transport : &HttpTransport,
) -> JsonHttpResponse {
  @provider.check_cancellation(cancellation_token)
  let response = fetch_buffered_with_timeout(
    provider_name,
    HttpRequest::post(url~, headers~, body~),
    timeout_ms,
    transport,
  )
  let response_body = @utf8.decode(
    read_response_with_size_limit(response, url~),
  )
  guard response.is_success() else {
    let error_json = parse_json_if_valid(response_body)
    let (message, retryable) = handle_failed_response(
      url~,
      request_body~,
      request_headers=headers,
      status_code=response.status_code,
      response_headers=response.headers,
      response_body~,
      error_json~,
      error_to_message,
      is_retryable_response,
    )
    raise @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers=copy_headers(headers),
      status_code=Some(response.status_code),
      response_headers=copy_headers(response.headers),
      response_body~,
      is_retryable=retryable,
      data=error_json,
      cause=None,
    )
  }
  let value = parse_successful_json_response(
    response_body,
    url,
    request_body,
    headers,
    response.status_code,
    response.headers,
  )
  validate_successful_json_response(
    value,
    validate_response,
    response_body,
    url,
    request_body,
    headers,
    response.status_code,
    response.headers,
  )
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
  error_to_message : ((Json) -> String? raise)?,
  is_retryable_response : ((Int, Json?) -> Bool? raise)?,
  validate_response : ((Json) -> Unit raise)?,
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
    validate_response,
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
  error_to_message? : (Json) -> String? raise,
  is_retryable_response? : (Int, Json?) -> Bool? raise,
  validate_response? : (Json) -> Unit raise,
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
        validate_response,
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

///|
async fn post_json_binary_once(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  timeout_ms : Int,
  cancellation_token : @provider.CancellationToken?,
  error_to_message : ((Json) -> String? raise)?,
  is_retryable_response : ((Int, Json?) -> Bool? raise)?,
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
  let value = if response.is_success() {
    response.body
  } else {
    read_response_with_size_limit(response, url~)
  }
  guard response.is_success() else {
    let response_body = binary_error_body(value)
    let error_json = parse_json_if_valid(response_body)
    let (message, retryable) = handle_failed_response(
      url~,
      request_body~,
      request_headers=headers,
      status_code=response.status_code,
      response_headers=response.headers,
      response_body~,
      error_json~,
      error_to_message,
      is_retryable_response,
    )
    raise @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers=copy_headers(headers),
      status_code=Some(response.status_code),
      response_headers=copy_headers(response.headers),
      response_body~,
      is_retryable=retryable,
      data=error_json,
      cause=None,
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
  error_to_message? : (Json) -> String? raise,
  is_retryable_response? : (Int, Json?) -> Bool? raise,
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
      error =>
        raise normalize_api_transport_error(
          error,
          url~,
          request_body=body.stringify(),
          request_headers=headers,
        )
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
  error_to_message? : (Json) -> String? raise,
  is_retryable_response? : (Int, Json?) -> Bool? raise,
  validate_response? : (Json) -> Unit raise,
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
        validate_response,
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
      error =>
        raise normalize_api_transport_error(
          error,
          url~,
          request_body=form_data.diagnostic_body,
          request_headers~,
        )
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
  error_to_message : ((Json) -> String? raise)?,
  is_retryable_response : ((Int, Json?) -> Bool? raise)?,
  validate_response : ((Json) -> Unit raise)?,
  transport : &HttpTransport,
) -> JsonHttpResponse {
  @provider.check_cancellation(cancellation_token)
  let response = fetch_buffered_with_timeout(
    provider_name,
    HttpRequest::get(url~, headers~),
    timeout_ms,
    transport,
  )
  let response_body = @utf8.decode(
    read_response_with_size_limit(response, url~),
  )
  let error_json = parse_json_if_valid(response_body)
  guard response.is_success() else {
    let (message, retryable) = handle_failed_response(
      url~,
      request_body="",
      request_headers=headers,
      status_code=response.status_code,
      response_headers=response.headers,
      response_body~,
      error_json~,
      error_to_message,
      is_retryable_response,
    )
    raise @provider.APICallError(
      message~,
      url~,
      request_body="",
      request_headers=copy_headers(headers),
      status_code=Some(response.status_code),
      response_headers=copy_headers(response.headers),
      response_body~,
      is_retryable=retryable,
      data=error_json,
      cause=None,
    )
  }
  let value = parse_successful_json_response(
    response_body,
    url,
    "",
    headers,
    response.status_code,
    response.headers,
  )
  validate_successful_json_response(
    value,
    validate_response,
    response_body,
    url,
    "",
    headers,
    response.status_code,
    response.headers,
  )
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
  error_to_message? : (Json) -> String? raise,
  is_retryable_response? : (Int, Json?) -> Bool? raise,
  validate_response? : (Json) -> Unit raise,
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
        validate_response,
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
      error =>
        raise normalize_api_transport_error(
          error,
          url~,
          request_body="",
          request_headers=headers,
        )
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
  trusted_origin : String?,
  max_bytes : Int64,
  transport : &HttpTransport,
  safe_transport : &HttpTransport?,
) -> DownloadedFile {
  let mut current_url = url
  let mut request_headers = sanitize_download_headers(headers)
  let mut redirect_count = 0
  for ;; {
    @provider.check_cancellation(cancellation_token)
    let is_trusted_hop = match trusted_origin {
      Some(origin) => download_same_origin(current_url, origin)
      None => false
    }
    if !is_trusted_hop {
      validate_download_url(current_url)
    }
    if current_url.length() >= 5 &&
      current_url[:5].to_owned().to_lower() == "data:" {
      let (data, media_type) = decode_data_url(current_url)
      ensure_download_size(current_url, data, max_bytes, None)
      let response_headers = { "content-type": media_type }
      return {
        data,
        media_type,
        response: @provider.ResponseMetadata::new(
          status_code=200,
          headers=response_headers,
        ),
      }
    }
    let hop_transport = match safe_transport {
      Some(value) if !is_trusted_hop => value
      _ => transport
    }
    let response = fetch_buffered_with_timeout(
      provider_name,
      HttpRequest::get(url=current_url, headers=request_headers),
      timeout_ms,
      hop_transport,
    )
    if is_download_redirect_status(response.status_code) &&
      download_response_header(response.headers, "location") is Some(location) {
      guard redirect_count < 10 else {
        raise DownloadError(
          url=current_url,
          message="Too many redirects (max 10)",
          status_code=None,
          status_text=None,
        )
      }
      let next_url = resolve_download_redirect(current_url, location)
      request_headers = download_redirect_headers(
        request_headers, current_url, next_url,
      )
      current_url = next_url
      redirect_count = redirect_count + 1
      continue
    }
    guard response.is_success() else {
      let status_text = if response.reason == "" {
        None
      } else {
        Some(response.reason)
      }
      raise DownloadError(
        url=current_url,
        message="Failed to download \{current_url}: \{response.status_code} \{response.reason}",
        status_code=Some(response.status_code),
        status_text~,
      )
    }
    let data = read_response_with_size_limit(
      response,
      url=current_url,
      max_bytes~,
    )
    let response_headers = copy_headers(response.headers)
    return {
      data,
      media_type: downloaded_media_type(response_headers),
      response: @provider.ResponseMetadata::new(
        status_code=response.status_code,
        headers=response_headers,
      ),
    }
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
  trusted_origin? : String,
  max_bytes? : Int64 = DEFAULT_MAX_DOWNLOAD_SIZE,
  transport? : &HttpTransport,
) -> DownloadedFile {
  guard max_bytes >= 0L else {
    raise download_error(url, "Maximum download size must not be negative")
  }
  let resolved_transport = transport.unwrap_or(native_http_transport())
  let safe_transport : &HttpTransport? = match transport {
    None => Some(safe_native_download_transport(max_bytes))
    Some(_) => None
  }
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
        trusted_origin,
        max_bytes,
        resolved_transport,
        safe_transport,
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

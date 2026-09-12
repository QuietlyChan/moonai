///|
test "failed response handler falls back to a status message for empty bodies" {
  let (message, retryable) = handle_failed_response(
    url="https://example.test/v1/chat",
    request_body="{}",
    request_headers=Map([]),
    status_code=502,
    response_headers=Map([]),
    response_body="",
    error_json=None,
    None,
    None,
  )
  assert_eq(message, "HTTP 502 error response")
  assert_true(retryable)
  // Non-empty bodies are preserved verbatim.
  let (plain, _) = handle_failed_response(
    url="https://example.test/v1/chat",
    request_body="{}",
    request_headers=Map([]),
    status_code=400,
    response_headers=Map([]),
    response_body="bad request",
    error_json=None,
    None,
    None,
  )
  assert_eq(plain, "bad request")
  let (extracted, _) = handle_failed_response(
    url="https://example.test/v1/chat",
    request_body="{}",
    request_headers=Map([]),
    status_code=429,
    response_headers=Map([]),
    response_body="",
    error_json=Some({ "error": { "message": "slow down" } }),
    Some(fn(value) {
      match value {
        { "error": { "message": String(message), .. } } => Some(message)
        _ => None
      }
    }),
    None,
  )
  assert_eq(extracted, "slow down")
}

///|
/// POST a JSON request and parse a successful JSON response. Provider packages
/// own protocol validation while this helper owns timeout and HTTP errors.
pub async fn post_json(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  timeout_ms? : Int = 120_000,
) -> Json {
  let result = if timeout_ms <= 0 {
    @http.post(url, body, headers~)
  } else {
    match
      @async.with_timeout_opt(timeout_ms, () => @http.post(url, body, headers~)) {
      Some(value) => value
      None => fail("\{provider_name} request timed out after \{timeout_ms}ms")
    }
  }
  let (response, response_data) = result
  let response_body = response_data.text()
  guard response.code >= 200 && response.code < 300 else {
    fail("\{provider_name} API error \{response.code}: \{response_body}")
  }
  @json.parse(response_body) catch {
    error =>
      fail(
        "\{provider_name} returned invalid JSON: \{error}; body: \{response_body}",
      )
  }
}

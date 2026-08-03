///|
test "copy_headers isolates provider configuration" {
  let source : Map[String, String] = { "Authorization": "old" }
  let copied = copy_headers(source)
  copied["Authorization"] = "new"
  assert_eq(source["Authorization"], "old")
  assert_eq(copied["Authorization"], "new")
}

///|
test "call headers override provider headers" {
  let merged = merge_headers(
    { "Authorization": "provider", "X-Provider": "moonai" },
    { "Authorization": "call", "X-Request-Id": "request-1" },
  )
  assert_eq(merged["Authorization"], "call")
  assert_eq(merged["X-Provider"], "moonai")
  assert_eq(merged["X-Request-Id"], "request-1")
}

///|
test "append_path normalizes one trailing slash and avoids duplicates" {
  assert_eq(
    append_path("https://example.com/v1/", "/responses"),
    "https://example.com/v1/responses",
  )
  assert_eq(
    append_path("https://example.com/v1/responses", "responses"),
    "https://example.com/v1/responses",
  )
}

///|
test "JSON field accessors reject mismatched values" {
  let value : Json = { "name": "moonai", "count": 3, "enabled": true }
  assert_eq(json_string_field(value, "name"), Some("moonai"))
  assert_eq(json_string_field(value, "enabled"), None)
  assert_eq(json_int_field_opt(value, "count"), Some(3))
  assert_eq(json_int_field(value, "missing", default=7), 7)
}

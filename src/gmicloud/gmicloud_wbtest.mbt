///|
test "gmicloud error message prefers the nested engine diagnostic" {
  assert_eq(
    gmicloud_error_to_message({
      "error": {
        "message": "request failed",
        "details": "{\"error\":{\"message\":\"CUDA out of memory\"}}",
      },
    }),
    Some("CUDA out of memory"),
  )
  assert_eq(
    gmicloud_error_to_message({
      "error": { "message": "request failed", "details": "not json" },
    }),
    Some("request failed"),
  )
  assert_eq(
    gmicloud_error_to_message({
      "error": {
        "message": "request failed",
        "details": "{\"error\":{\"message\":\"  \"}}",
      },
    }),
    Some("request failed"),
  )
  assert_eq(
    gmicloud_error_to_message({ "error": { "message": "plain" } }),
    Some("plain"),
  )
  assert_eq(gmicloud_error_to_message({ "error": {} }), None)
}

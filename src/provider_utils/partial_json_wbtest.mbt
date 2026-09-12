///|
test "debug" {
  let result = parse_partial_json("{\"n\": 5, \"ok\": tr")
  match result.value {
    { "n": _, "ok": ok, .. } => println("OK=" + (ok is True).to_string())
    _ => println("SHAPE_OTHER")
  }
}

///|
test "partial json repair completes a truncated literal" {
  let bytes = @utf8.encode("{\"n\": 5, \"ok\": tr")
  let repaired = repair_partial_prefix(bytes, bytes.length())
  // Print the actual repair output for inspection.
  match repaired {
    Some(text) => println("REPAIRED=" + text)
    None => println("REPAIRED=None")
  }
  assert_true(repaired is Some(text) && text.has_suffix("true}"))
}

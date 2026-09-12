///|
test "partial json parses complete values directly" {
  let result = parse_partial_json("{\"a\": 1, \"b\": [true, null]}")
  assert_eq(result.state, PartialSuccessfulParse)
  assert_true(result.value is { "a": Number(_), "b": Array([True, Null]), .. })
}

///|
test "partial json repairs a truncated string value" {
  let result = parse_partial_json("{\"a\": \"Hello wo")
  assert_eq(result.state, PartialSuccessfulRepair)
  assert_true(result.value is { "a": String("Hello wo"), .. })
}

///|
test "partial json repairs nested containers" {
  let result = parse_partial_json(
    "{\"items\": [{\"id\": 1}, {\"id\": 2}, {\"id\": 3",
  )
  assert_eq(result.state, PartialSuccessfulRepair)
  match result.value {
    { "items": Array(values), .. } => assert_eq(values.length(), 3)
    _ => fail("expected items array")
  }
}

///|
test "partial json repairs truncated arrays" {
  let result = parse_partial_json("[1, 2, ")
  assert_eq(result.state, PartialSuccessfulRepair)
  match result.value {
    Array(values) => assert_eq(values.length(), 2)
    _ => fail("expected an array")
  }
}

///|
test "partial json drops a truncated number member" {
  let result = parse_partial_json("{\"n\": 1.5e")
  assert_eq(result.state, PartialSuccessfulRepair)
  match result.value {
    { "n": Null, .. } => assert_true(true)
    _ => fail("expected n to be null")
  }
}

///|
test "partial json returns undefined for empty input" {
  let result = parse_partial_json("   ")
  assert_eq(result.state, PartialUndefinedInput)
}

///|
test "partial json fails on garbage that cannot be repaired" {
  let result = parse_partial_json("not json at all {")
  assert_eq(result.state, PartialFailedParse)
}

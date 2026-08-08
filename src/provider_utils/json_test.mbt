///|
test "is_record accepts only JSON objects" {
  assert_true(is_record({ "value": 1 }))
  assert_true(isRecord(Json::empty_object()))
  assert_false(is_record([1, 2, 3]))
  assert_false(is_record(Json::null()))
  assert_false(is_record("value"))
  assert_false(is_record(42))
  assert_false(is_record(true))
}

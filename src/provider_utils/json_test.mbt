///|
test "is_record accepts only JSON objects" {
  assert_true(@provider_utils.is_record({ "value": 1 }))
  assert_true(@provider_utils.isRecord(Json::empty_object()))
  assert_false(@provider_utils.is_record([1, 2, 3]))
  assert_false(@provider_utils.is_record(Json::null()))
  assert_false(@provider_utils.is_record("value"))
  assert_false(@provider_utils.is_record(42))
  assert_false(@provider_utils.is_record(true))
}

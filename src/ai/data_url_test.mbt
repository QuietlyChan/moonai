///|
test "get_text_from_data_url decodes base64 text payloads" {
  assert_eq(get_text_from_data_url("data:text/plain;base64,aGk="), "hi")
  assert_eq(
    get_text_from_data_url("data:text/plain;charset=utf-8;base64,5L2g5aW9"),
    "你好",
  )
}

///|
test "get_text_from_data_url rejects malformed data URLs (#20304)" {
  try get_text_from_data_url("not-a-data-url") catch {
    InvalidArgumentError(parameter~, value~, message~) => {
      assert_eq(parameter, "dataUrl")
      assert_eq(value, Json::string("not-a-data-url"))
      assert_eq(
        message, "Invalid argument for parameter dataUrl: Invalid data URL format",
      )
    }
  } noraise {
    _ => fail("expected InvalidArgumentError")
  }
  try get_text_from_data_url("data,SGVsbG8=") catch {
    InvalidArgumentError(message~, ..) =>
      assert_eq(
        message, "Invalid argument for parameter dataUrl: Invalid data URL format",
      )
  } noraise {
    _ => fail("expected InvalidArgumentError")
  }
}

///|
test "get_text_from_data_url rejects undecodable payloads (#20304)" {
  try get_text_from_data_url("data:text/plain;base64,invalid-base64") catch {
    InvalidArgumentError(parameter~, message~, ..) => {
      assert_eq(parameter, "dataUrl")
      assert_eq(
        message, "Invalid argument for parameter dataUrl: Error decoding data URL",
      )
    }
  } noraise {
    _ => fail("expected InvalidArgumentError")
  }
}

///|
test "EventSourceBuffer joins multiline data and ignores other fields" {
  let buffer = EventSourceBuffer::new()
  assert_eq(buffer.feed_line("event: message"), None)
  assert_eq(buffer.feed_line("data: {\"value\":"), None)
  assert_eq(buffer.feed_line("data: 1}"), None)
  assert_eq(buffer.feed_line(""), Some("{\"value\":\n1}"))
}

///|
test "EventSourceBuffer flushes an unterminated payload" {
  let buffer = EventSourceBuffer::new()
  assert_eq(buffer.feed_line("data: [DONE]"), None)
  assert_eq(buffer.flush(), Some("[DONE]"))
  assert_eq(buffer.flush(), None)
}

///|
test "EventSourceBuffer follows SSE data whitespace rules" {
  let buffer = EventSourceBuffer::new()
  assert_eq(buffer.feed_line("data:  keep one leading space"), None)
  assert_eq(buffer.feed_line("data"), None)
  assert_eq(buffer.feed_line(""), Some(" keep one leading space\n"))
}

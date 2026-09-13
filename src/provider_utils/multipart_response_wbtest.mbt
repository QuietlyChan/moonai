///|
fn multipart_wbtest_body() -> Bytes {
  let out = @buffer.Buffer()
  let write = s => {
    for ch in @utf8.encode(s) {
      out.write_byte(ch)
    }
  }
  write("--XX\r\n")
  write("content-disposition: form-data; name=\"job\"\r\n")
  write("content-type: application/json\r\n")
  write("\r\n")
  write("{\"id\":\"job-1\"}\r\n")
  write("--XX\r\n")
  write("content-disposition: form-data; name=\"output\"\r\n")
  write("content-type: image/png\r\n")
  write("\r\n")
  out.write_byte(0x89)
  out.write_byte(0x50)
  out.write_byte(0x4e)
  out.write_byte(0x47)
  write("\r\n--XX--\r\n")
  out.to_bytes()
}

///|
test "multipart response splits job and output parts" {
  let parts = parse_multipart_response(
    content_type="multipart/form-data; boundary=XX",
    data=multipart_wbtest_body(),
  )
  assert_eq(parts.length(), 2)
  let job = multipart_response_part_by_name(parts, name="job")
  assert_eq(
    job.unwrap_or({ headers: Map([]), body: Bytes::make(0, 0), }).headers.get(
      "content-type",
    ),
    Some("application/json"),
  )
  assert_eq(
    @utf8.decode(
      job.unwrap_or({ headers: Map([]), body: Bytes::make(0, 0), }).body,
    ),
    "{\"id\":\"job-1\"}",
  )
  let output = multipart_response_part_by_name(parts, name="output")
  let body = output.unwrap_or({ headers: Map([]), body: Bytes::make(0, 0), }).body
  assert_eq(body.length(), 4)
}

///|
test "multipart boundary extraction handles quoted and unquoted" {
  assert_eq(multipart_boundary("multipart/form-data; boundary=XX"), Some("XX"))
  assert_eq(
    multipart_boundary("multipart/form-data; boundary=\"YY\""),
    Some("YY"),
  )
  assert_eq(multipart_boundary("application/json"), None)
}

///|
test "multipart by content type prefix falls back to media type" {
  let parts = parse_multipart_response(
    content_type="multipart/form-data; boundary=XX",
    data=multipart_wbtest_body(),
  )
  assert_true(
    multipart_response_part_by_content_type_prefix(parts, prefix="image/")
    is Some(_),
  )
}

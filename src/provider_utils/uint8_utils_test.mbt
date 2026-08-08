///|
test "byte and Base64 conversion follows AI SDK semantics" {
  assert_eq(convert_base64_to_bytes("SGVsbG8="), b"Hello")
  assert_eq(convertBase64ToUint8Array("-_8"), b"\xfb\xff")
  assert_eq(convert_base64_to_bytes("SGVs\nbG8"), b"Hello")
  assert_eq(convert_bytes_to_base64(b"Hello"), "SGVsbG8=")
  assert_eq(convertUint8ArrayToBase64(b"\xfb\xff"), "+/8=")
  assert_eq(
    convert_to_base64(@provider.V4FileData("YWxyZWFkeQ==")),
    "YWxyZWFkeQ==",
  )
  assert_eq(convertToBase64(@provider.V4FileBytes(b"MoonBit")), "TW9vbkJpdA==")
}

///|
test "inline file data converts bytes, Base64, and UTF-8 text" {
  assert_eq(
    convert_inline_file_data_to_bytes(@provider.UploadFileData::bytes(b"raw")),
    b"raw",
  )
  assert_eq(
    convert_inline_file_data_to_bytes(
      @provider.UploadFileData::base64("TW9vbkJpdA=="),
    ),
    b"MoonBit",
  )
  assert_eq(
    convertInlineFileDataToUint8Array(
      @provider.UploadFileData::text("MoonBit \u{6708}"),
    ),
    b"MoonBit \xe6\x9c\x88",
  )
}

///|
test "invalid Base64 data is rejected" {
  try convert_base64_to_bytes("not/base64%") catch {
    _ => ()
  } noraise {
    _ => fail("expected invalid Base64 data to raise")
  }
}

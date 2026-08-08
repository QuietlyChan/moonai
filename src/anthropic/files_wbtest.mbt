///|
test "Anthropic Files preserves a successful response error as typed data" {
  let options = @provider.FilesV4UploadFileCallOptions::new(
    data=@provider.UploadFileData::text("MoonBit"),
    media_type="text/plain",
  )
  try
    decode_anthropic_file_upload(
      { "error": { "message": "permission denied" } },
      options,
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("permission denied"))
      assert_true(data is { "error": { .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed Anthropic Files response error")
  }
}

///|
test "Anthropic Files rejects a successful response without an id" {
  let options = @provider.FilesV4UploadFileCallOptions::new(
    data=@provider.UploadFileData::text("MoonBit"),
    media_type="text/plain",
  )
  try decode_anthropic_file_upload({ "type": "file" }, options) catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("no file id"))
      assert_true(data is { "type": "file", .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed missing-id response error")
  }
}

///|
test "OpenAI Files preserves a successful response error as typed data" {
  let options = @provider.FileUploadOptions::new(
    data=@provider.UploadFileData::text("MoonBit"),
    media_type="text/plain",
  )
  let parsed = parse_openai_files_options(options, "openai.files")
  try
    decode_openai_file_upload(
      { "error": { "message": "quota exceeded" } },
      options,
      parsed,
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("quota exceeded"))
      assert_true(data is { "error": { .. }, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed OpenAI Files response error")
  }
}

///|
test "OpenAI Files rejects a successful response without an id" {
  let options = @provider.FileUploadOptions::new(
    data=@provider.UploadFileData::text("MoonBit"),
    media_type="text/plain",
  )
  let parsed = parse_openai_files_options(options, "openai.files")
  try decode_openai_file_upload({ "object": "file" }, options, parsed) catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("no file id"))
      assert_true(data is { "object": "file", .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a typed missing-id response error")
  }
}

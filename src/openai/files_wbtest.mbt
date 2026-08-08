///|
test "OpenAI Files preserves a successful response error as typed data" {
  let options = @provider.FilesV4UploadFileCallOptions::new(
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
  let options = @provider.FilesV4UploadFileCallOptions::new(
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

///|
test "OpenAI Files keeps options in the official namespace" {
  let options = @provider.FilesV4UploadFileCallOptions::new(
    data=@provider.UploadFileData::text("MoonBit"),
    media_type="text/plain",
    provider_options={
      "localOpenAI": { "purpose": "custom-purpose" },
      "openai": { "purpose": "assistants", "expiresAfter": 3600 },
    },
  )
  let parsed = parse_openai_files_options(options, "localOpenAI.files")
  assert_eq(parsed.options.purpose, Some("assistants"))
  assert_eq(parsed.options.expires_after, Some(3600.0))
}

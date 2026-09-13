///|
test "DeepSeek files options reject out-of-range expiry" {
  let parsed = parse_deepseek_files_options(
    Map([("deepseek", { "expiresAfter": 600 })]),
  )
  assert_true(parsed.expires_after is None)
  assert_eq(parsed.warnings.length(), 1)
  let parsed_valid = parse_deepseek_files_options(
    DeepSeekFilesOptions::new(expires_after=7200.0).to_provider_options(),
  )
  assert_eq(parsed_valid.expires_after, Some(7200))
  assert_eq(parsed_valid.warnings.length(), 0)
}

///|
test "DeepSeek file uploads reject unsupported detected content" {
  let outcome = try {
    guard_deepseek_files_media_type(
      media_type="application/binary",
      filename=Some("notes.bin"),
      file_bytes=b"plain text, not an image",
    )
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.InvalidArgumentError(_)))
}

///|
test "DeepSeek file uploads accept generic media types with image content" {
  // PNG magic bytes: the detected content type overrides the generic
  // declared media type.
  guard_deepseek_files_media_type(
    media_type="application/binary",
    filename=None,
    file_bytes=b"\x89PNG\r\n\x1a\n\x00\x00",
  )
}

///|
test "DeepSeek file uploads accept supported filename extensions" {
  guard_deepseek_files_media_type(
    media_type="application/binary",
    filename=Some("drawing.WEBP"),
    file_bytes=b"\x00\x00\x00\x00",
  )
}

///|
test "DeepSeek file uploads reject unsupported declared media types" {
  let outcome = try {
    guard_deepseek_files_media_type(
      media_type="video/mp4",
      filename=Some("clip.mp4"),
      file_bytes=b"\x00\x00\x00\x00",
    )
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.InvalidArgumentError(_)))
}

///|
test "DeepSeek file uploads reject over-long filenames" {
  let outcome = try {
    guard_deepseek_files_filename("f".repeat(513))
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.InvalidArgumentError(_)))
}

///|
test "DeepSeek file upload decode builds provider references and metadata" {
  let result = decode_deepseek_file_upload(
    {
      "id": "file-1",
      "object": "file",
      "filename": "cat.png",
      "purpose": "user_data",
      "bytes": 1024,
      "created_at": 1700000000,
      "expires_at": 1700003600,
    },
    @provider.FilesV4UploadFileCallOptions::new(
      data=@provider.UploadFileData::text("x"),
      media_type="image/png",
      filename="cat.png",
    ),
    warnings=[],
  )
  assert_eq(result.provider_reference.get("deepseek"), Some("file-1"))
  assert_eq(result.filename, Some("cat.png"))
  assert_eq(result.byte_size, Some(1024))
  assert_eq(result.created_at, Some(1700000000))
  assert_eq(result.expires_at, Some(1700003600))
}

///|
test "DeepSeek file upload decode requires an id" {
  let outcome = try {
    let _ = decode_deepseek_file_upload(
      { "purpose": "user_data" },
      @provider.FilesV4UploadFileCallOptions::new(
        data=@provider.UploadFileData::text("x"),
        media_type="image/png",
      ),
      warnings=[],
    )
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.InvalidResponseDataError(_)))
}

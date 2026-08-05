///|
async test "official OpenAI Files uploads multipart data and returns a reference" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/files")
          assert_true(
            request.headers.get("authorization") is Some("Bearer test-key"),
          )
          assert_true(
            request.headers.get("openai-organization") is Some("org-test"),
          )
          assert_true(
            request.headers.get("openai-project") is Some("project-test"),
          )
          assert_true(
            request.headers
            .get("content-type")
            .unwrap_or("")
            .contains("multipart/form-data; boundary="),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("name=\"file\""))
          assert_true(request_body.contains("filename=\"moonbit.txt\""))
          assert_true(request_body.contains("Content-Type: text/plain"))
          assert_true(request_body.contains("MoonBit file"))
          assert_true(
            request_body.contains("name=\"purpose\"\r\n\r\nfine-tune"),
          )
          assert_true(
            request_body.contains(
              "name=\"expires_after[anchor]\"\r\n\r\ncreated_at",
            ),
          )
          assert_true(
            request_body.contains("name=\"expires_after[seconds]\"\r\n\r\n3600"),
          )
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"file-abc123\",\"object\":\"file\",\"bytes\":12,\"created_at\":1700000000,\"filename\":\"server-name.txt\",\"purpose\":\"fine-tune\",\"status\":\"processed\",\"expires_at\":1700003600}",
          )
        },
        max_connections=1,
      )
    }
    let provider = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      organization="org-test",
      project="project-test",
      idle_timeout_ms=2_000,
    )
    let files = provider.files()
    assert_eq(files.provider(), "openai.files")
    let result = @ai.upload_file(
      files,
      data=@provider.UploadFileData::text("MoonBit file"),
      media_type="text/plain",
      filename="moonbit.txt",
      provider_options=OpenAIFilesOptions::new(
        purpose="fine-tune",
        expires_after=3600.0,
      ).to_provider_options(),
    )
    assert_eq(result.provider_reference.get("openai"), Some("file-abc123"))
    assert_eq(result.media_type, Some("text/plain"))
    assert_eq(result.filename, Some("server-name.txt"))
    assert_eq(result.warnings, [])
    json_inspect(result.provider_metadata["openai"], content={
      "filename": "server-name.txt",
      "purpose": "fine-tune",
      "bytes": 12,
      "createdAt": 1700000000,
      "status": "processed",
      "expiresAt": 1700003600,
    })
  }
}

///|
async test "official OpenAI Files accepts Base64 and defaults upload fields" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          let request_body = body.read_all().text()
          assert_true(request_body.contains("filename=\"blob\""))
          assert_true(request_body.contains("hello world"))
          assert_true(
            request_body.contains("name=\"purpose\"\r\n\r\nassistants"),
          )
          assert_false(request_body.contains("expires_after[anchor]"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"file-base64\",\"object\":\"file\",\"bytes\":11,\"created_at\":1700000000,\"purpose\":\"assistants\",\"status\":\"processed\",\"expires_at\":null}",
          )
        },
        max_connections=1,
      )
    }
    let files = create_openai(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    ).files()
    let result = @ai.uploadFile(
      files,
      data=@provider.UploadFileData::base64("aGVsbG8gd29ybGQ="),
      media_type="application/octet-stream",
    )
    assert_eq(result.provider_reference.get("openai"), Some("file-base64"))
    assert_eq(result.filename, None)
    json_inspect(result.provider_metadata["openai"], content={
      "purpose": "assistants",
      "bytes": 11,
      "createdAt": 1700000000,
      "status": "processed",
    })
  }
}

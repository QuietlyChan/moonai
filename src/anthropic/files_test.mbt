///|
async test "official Anthropic Files uploads multipart data and maps metadata" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/files")
          assert_true(request.headers.get("x-api-key") is Some("test-key"))
          assert_true(
            request.headers.get("anthropic-version") is Some("2023-06-01"),
          )
          assert_true(
            request.headers.get("anthropic-beta")
            is Some("files-api-2025-04-14"),
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
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"file-abc123\",\"type\":\"file\",\"filename\":\"server-name.txt\",\"mime_type\":\"text/plain\",\"size_bytes\":12,\"created_at\":\"2025-04-14T12:00:00Z\",\"downloadable\":true}",
          )
        },
        max_connections=1,
      )
    }
    let files = create_anthropic(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    ).files()
    assert_eq(files.provider(), "anthropic.messages")
    let result = @ai.upload_file(
      files,
      data=@provider.UploadFileData::text("MoonBit file"),
      media_type="text/plain",
      filename="moonbit.txt",
    )
    assert_eq(result.provider_reference.get("anthropic"), Some("file-abc123"))
    assert_eq(result.media_type, Some("text/plain"))
    assert_eq(result.filename, Some("server-name.txt"))
    assert_eq(result.warnings, [])
    json_inspect(result.provider_metadata["anthropic"], content={
      "filename": "server-name.txt",
      "mimeType": "text/plain",
      "sizeBytes": 12,
      "createdAt": "2025-04-14T12:00:00Z",
      "downloadable": true,
    })
  }
}

///|
async test "Anthropic Files uses bearer auth and defaults the upload filename" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_true(
            request.headers.get("authorization") is Some("Bearer auth-token"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("filename=\"blob\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"file-auth\",\"type\":\"file\",\"filename\":\"blob\",\"mime_type\":\"application/octet-stream\",\"size_bytes\":3,\"created_at\":\"2025-04-14T12:00:00Z\",\"downloadable\":null}",
          )
        },
        max_connections=1,
      )
    }
    let files = anthropic_files(
      auth_token="auth-token",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
    )
    let result = @ai.uploadFile(
      files,
      data=@provider.UploadFileData::text("abc"),
      media_type="application/octet-stream",
    )
    assert_eq(result.provider_reference.get("anthropic"), Some("file-auth"))
    assert_eq(result.filename, Some("blob"))
    json_inspect(result.provider_metadata["anthropic"], content={
      "filename": "blob",
      "mimeType": "application/octet-stream",
      "sizeBytes": 3,
      "createdAt": "2025-04-14T12:00:00Z",
    })
  }
}

///|
async test "DeepSeek Files uploads user_data images and returns a reference" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/files")
          assert_true(
            request.headers.get("authorization") is Some("Bearer test-key"),
          )
          assert_true(
            request.headers
            .get("content-type")
            .unwrap_or("")
            .contains("multipart/form-data; boundary="),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("name=\"file\""))
          assert_true(request_body.contains("filename=\"photo.png\""))
          assert_true(request_body.contains("Content-Type: image/png"))
          assert_true(
            request_body.contains("name=\"purpose\"\r\n\r\nuser_data"),
          )
          assert_true(
            request_body.contains(
              "name=\"expires_after[anchor]\"\r\n\r\ncreated_at",
            ),
          )
          assert_true(
            request_body.contains("name=\"expires_after[seconds]\"\r\n\r\n7200"),
          )
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"id\":\"file-abc123\",\"object\":\"file\",\"bytes\":8,\"created_at\":1700000000,\"filename\":\"photo.png\",\"purpose\":\"user_data\",\"expires_at\":1700007200}",
          )
        },
        max_connections=1,
      )
    }
    let provider = createDeepSeek(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}",
      idle_timeout_ms=2_000,
    )
    let files = DeepSeekProvider::files(provider)
    assert_eq(files.specification_version(), "v4")
    assert_eq(files.provider(), "deepseek.files")
    let result = @ai.upload_file(
      files,
      data=@provider.UploadFileData::bytes(b"PNGDATA!"),
      media_type="image/png",
      filename="photo.png",
      provider_options=DeepSeekFilesOptions::new(expires_after=7200.0).to_provider_options(),
    )
    assert_eq(result.provider_reference.get("deepseek"), Some("file-abc123"))
    assert_eq(result.filename, Some("photo.png"))
    assert_eq(result.byte_size, Some(8))
    assert_eq(result.created_at, Some(1700000000))
    assert_eq(result.expires_at, Some(1700007200))
    match result.provider_metadata.get("deepseek") {
      Some(Object(fields)) => {
        assert_eq(fields.get("purpose"), Some(Json::string("user_data")))
        assert_eq(fields.get("object"), Some(Json::string("file")))
      }
      _ => fail("expected deepseek provider metadata")
    }
  }
}

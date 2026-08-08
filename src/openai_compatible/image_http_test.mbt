///|
async test "generateImage batches OpenAI-compatible image requests" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let mut request_count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/images/generations")
          assert_true(
            request.headers.get("x-request-id") is Some("image-generate"),
          )
          let request_body = body.read_all().text()
          assert_true(request_body.contains("\"model\":\"image-model\""))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          if request_count == 0 {
            assert_true(request_body.contains("\"n\":2"))
            connection.write(
              "{\"id\":\"image-1\",\"model\":\"image-model\",\"created\":1700000020,\"provider_metadata\":{\"local-test.image\":{\"first_batch\":true}},\"data\":[{\"b64_json\":\"image-1\"},{\"b64_json\":\"image-2\"}],\"usage\":{\"input_tokens\":2,\"output_tokens\":4,\"total_tokens\":6}}",
            )
          } else {
            assert_true(request_body.contains("\"n\":1"))
            connection.write(
              "{\"id\":\"image-2\",\"model\":\"image-model\",\"provider_metadata\":{\"local-test.image\":{\"last_batch\":true}},\"data\":[{\"b64_json\":\"image-3\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}",
            )
          }
          request_count = request_count + 1
        },
        max_connections=2,
      )
    }
    let model = openai_compatible_image(
      provider_name="local-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="image-model",
      api_key="test-key",
      max_images_per_call=2,
      idle_timeout_ms=2_000,
    )
    let response = @ai.generateImage(
      model,
      "A MoonBit logo",
      n=3,
      size="1024x1024",
      headers={ "X-Request-Id": "image-generate" },
    )
    assert_eq(response.images.length(), 3)
    assert_eq(response.images[0].data, @provider.ImageData::Base64("image-1"))
    assert_eq(response.images[2].data, @provider.ImageData::Base64("image-3"))
    assert_eq(response.usage.total_tokens, 9)
    assert_eq(response.response.unwrap().id, Some("image-1"))
    assert_eq(response.response.unwrap().created_at, Some(1700000020))
    json_inspect(response.provider_metadata["local-test.image"], content={
      "first_batch": true,
      "last_batch": true,
    })
  }
}

///|
async test "OpenAI-compatible image edits use multipart files and mask" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/images/edits")
          let content_type = request.headers.get("content-type").unwrap_or("")
          assert_true(content_type.contains("multipart/form-data; boundary="))
          let request_body = body.read_all().text()
          assert_true(
            request_body.contains("name=\"model\"\r\n\r\nimage-model"),
          )
          assert_true(request_body.contains("name=\"image[]\""))
          assert_true(request_body.contains("filename=\"image\""))
          assert_true(request_body.contains("name=\"mask\""))
          assert_true(request_body.contains("name=\"quality\"\r\n\r\nhigh"))
          assert_true(request_body.contains("FIRST-IMAGE"))
          assert_true(request_body.contains("SECOND-IMAGE"))
          assert_true(request_body.contains("MASK-IMAGE"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"data\":[{\"b64_json\":\"edited-1\"},{\"b64_json\":\"edited-2\"}]}",
          )
        },
        max_connections=1,
      )
    }
    let model = openai_compatible_image(
      provider_name="local-test",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      model_id="image-model",
      api_key="test-key",
      idle_timeout_ms=2_000,
    )
    let response = @ai.generateImage(
      model,
      "Edit both images",
      n=2,
      files=[
        @provider.ImageModelV4File::base64(
          data="RklSU1QtSU1BR0U=",
          media_type="image/png",
        ),
        @provider.ImageModelV4File::bytes(
          data=b"SECOND-IMAGE",
          media_type="image/png",
        ),
      ],
      mask=@provider.ImageModelV4File::bytes(
        data=b"MASK-IMAGE",
        media_type="image/png",
      ),
      provider_options={ "localTest": { "quality": "high" } },
    )
    assert_eq(response.images.length(), 2)
    assert_eq(response.images[0].data, @provider.ImageData::Base64("edited-1"))
    assert_eq(response.response.unwrap().model_id, Some("image-model"))
    assert_true(response.response.unwrap().created_at is Some(_))
    assert_true(response.request.unwrap().body.contains("bytes=11"))
    assert_true(!response.request.unwrap().body.contains("FIRST-IMAGE"))
  }
}

///|
async test "OpenAI-compatible image edits download URL-backed files" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          if request.path == "/asset.png" {
            let _ = body.read_all()
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "image/png; charset=binary",
            })
            connection.write("DOWNLOADED-IMAGE")
          } else {
            assert_eq(request.path, "/v1/images/edits")
            let request_body = body.read_all().text()
            assert_true(request_body.contains("Content-Type: image/png"))
            assert_true(request_body.contains("DOWNLOADED-IMAGE"))
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write("{\"data\":[{\"b64_json\":\"edited\"}]}")
          }
        },
        max_connections=2,
      )
    }
    let base_url = "http://127.0.0.1:\{server.addr.port()}"
    let model = openai_compatible_image(
      provider_name="local-test",
      base_url="\{base_url}/v1",
      model_id="image-model",
      idle_timeout_ms=2_000,
    )
    let response = @ai.generate_image(model, "Edit URL input", files=[
      @provider.ImageModelV4File::url("\{base_url}/asset.png"),
    ])
    assert_eq(response.images[0].data, @provider.ImageData::Base64("edited"))
  }
}

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
              "{\"id\":\"image-2\",\"model\":\"image-model\",\"provider_metadata\":{\"local-test.image\":{\"last_batch\":true}},\"data\":[{\"url\":\"https://example.com/image-3.png\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}",
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
    let response = @moonai.generateImage(
      model,
      "A MoonBit logo",
      n=3,
      size="1024x1024",
      headers={ "X-Request-Id": "image-generate" },
    )
    assert_eq(response.images.length(), 3)
    assert_eq(response.images[0].data, @moonai.ImageData::Base64("image-1"))
    assert_eq(
      response.images[2].data,
      @moonai.ImageData::Url("https://example.com/image-3.png"),
    )
    assert_eq(response.usage.total_tokens, 9)
    assert_eq(response.response.unwrap().id, Some("image-1"))
    assert_eq(response.response.unwrap().created_at, Some(1700000020))
    json_inspect(response.provider_metadata["local-test.image"], content={
      "first_batch": true,
      "last_batch": true,
    })
  }
}

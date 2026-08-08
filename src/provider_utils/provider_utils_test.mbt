///|
test "copy_headers isolates provider configuration" {
  let source : Map[String, String] = { "Authorization": "old" }
  let copied = copy_headers(source)
  copied["Authorization"] = "new"
  assert_eq(source["Authorization"], "old")
  assert_eq(copied["Authorization"], "new")
}

///|
test "call headers override provider headers" {
  let merged = merge_headers(
    { "Authorization": "provider", "X-Provider": "moonai" },
    { "authorization": "call", "X-Request-Id": "request-1" },
  )
  assert_eq(merged.get("Authorization"), None)
  assert_eq(merged["authorization"], "call")
  assert_eq(merged["X-Provider"], "moonai")
  assert_eq(merged["X-Request-Id"], "request-1")
}

///|
test "header utility aliases match AI SDK record behavior" {
  let first = { "Authorization": "provider", "X-First": "one" }
  let second = { "Authorization": "call", "X-Second": "two" }
  let combined = combineHeaders([first, second])
  assert_eq(combined["Authorization"], "call")
  assert_eq(combined["X-First"], "one")
  assert_eq(combined["X-Second"], "two")
  let normalized = normalizeHeaders(combined)
  assert_eq(normalized.get("Authorization"), None)
  assert_eq(normalized["authorization"], "call")
  assert_eq(first["Authorization"], "provider")
}

///|
test "request header sanitizer removes untrusted forwarding headers" {
  let input = {
    "Host": "metadata.internal",
    "Connection": "keep-alive",
    "X-Forwarded-For": "127.0.0.1",
    "Metadata-Flavor": "Google",
    "Cookie": "session=secret",
    "Authorization": "Bearer provider-token",
    "User-Agent": "moonai-test",
    "X-Request-Id": "request-1",
  }
  let sanitized = sanitizeRequestHeaders(input)
  assert_eq(sanitized.get("Host"), None)
  assert_eq(sanitized.get("Connection"), None)
  assert_eq(sanitized.get("X-Forwarded-For"), None)
  assert_eq(sanitized.get("Metadata-Flavor"), None)
  assert_eq(sanitized.get("Cookie"), None)
  assert_eq(sanitized.get("Authorization"), Some("Bearer provider-token"))
  assert_eq(sanitized.get("User-Agent"), Some("moonai-test"))
  assert_eq(sanitized.get("X-Request-Id"), Some("request-1"))
  assert_eq(input.get("Host"), Some("metadata.internal"))
}

///|
test "user agent suffix appends case-insensitively without mutating input" {
  let headers = {
    "User-Agent": "moon-app/1.0",
    "Authorization": "Bearer token",
  }
  let result = with_user_agent_suffix(headers, [
    "moonai/0.1.0", "provider/open-responses",
  ])
  assert_eq(
    result.get("user-agent"),
    Some("moon-app/1.0 moonai/0.1.0 provider/open-responses"),
  )
  assert_eq(result.get("Authorization"), Some("Bearer token"))
  assert_eq(headers.get("User-Agent"), Some("moon-app/1.0"))
}

///|
test "AI SDK-style user agent alias shares the header normalization" {
  let result = withUserAgentSuffix({ "User-Agent": "moon-app/1.0" }, [
    "moonai/0.1.0",
  ])
  assert_eq(result.get("user-agent"), Some("moon-app/1.0 moonai/0.1.0"))
}

///|
test "append_query percent-encodes UTF-8 keys and values" {
  assert_eq(
    append_query("https://example.com/v1/models", { "name": "Moon Bit/月" }),
    "https://example.com/v1/models?name=Moon%20Bit%2F%E6%9C%88",
  )
}

///|
test "provider options prefer camel-case namespaces and protect request fields" {
  let resolution = resolve_provider_options(
    { "openaiCompatible": { "reasoning_effort": "high", "stream": false } },
    provider_name="openai-compatible.chat",
    reserved_fields=["stream"],
  )
  json_inspect(resolution.values, content={ "reasoning_effort": "high" })
  assert_eq(resolution.warnings.length(), 1)
  assert_true(resolution.warnings[0] is @provider.Compatibility(..))
}

///|
test "provider options can preserve an exact configurable provider key" {
  let resolution = resolve_provider_options(
    { "local-v4": { "reasoningSummary": "detailed" } },
    provider_name="local-v4",
    prefer_exact_provider_name=true,
  )
  assert_eq(resolution.namespace_key, Some("local-v4"))
  assert_eq(resolution.warnings, [])
  assert_eq(resolution.values["reasoningSummary"], "detailed")
}

///|
test "exact provider option keys retain dotted configurable names" {
  let resolution = resolve_provider_options(
    { "local.responses": { "reasoningSummary": "auto" } },
    provider_name=" local.responses ",
    prefer_exact_provider_name=true,
  )
  assert_eq(resolution.namespace_key, Some("local.responses"))
  assert_eq(resolution.values["reasoningSummary"], "auto")
}

///|
test "flat provider options are ignored" {
  let resolution = resolve_provider_options(
    { "quality": "high" },
    provider_name="openai-compatible.image",
  )
  assert_eq(resolution.values.length(), 0)
  assert_eq(resolution.warnings, [])
  assert_eq(resolution.namespace_key, None)
}

///|
test "base URL validation preserves valid values and rejects blanks" {
  assert_eq(
    validate_base_url(Some("https://example.com/v1/")),
    Some("https://example.com/v1/"),
  )
  assert_eq(validate_base_url(None), None)
  try validate_base_url(Some("  ")) catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "baseURL")
      assert_eq(message, "baseURL must be a non-empty string.")
    }
  } noraise {
    _ => fail("expected an invalid base URL error")
  }
}

///|
test "provider options ignore namespaces owned by another provider" {
  let resolution = resolve_provider_options(
    { "anthropic": { "thinking": { "type": "adaptive" } } },
    provider_name="openai.responses",
  )
  assert_eq(resolution.values.length(), 0)
  assert_eq(resolution.warnings, [])
  assert_eq(resolution.namespace_key, None)
}

///|
test "typed provider option reader validates aliases and extension fields" {
  let resolution = resolve_provider_options(
    {
      "localTest": {
        "reasoning_summary": "detailed",
        "enabled": "yes",
        "extension": { "mode": "fast" },
      },
    },
    provider_name="local-test.responses",
  )
  let reader = ProviderOptionsReader::new(
    resolution,
    path="providerOptions.localTest",
  )
  assert_eq(
    reader.take_string("reasoningSummary", aliases=["reasoning_summary"], allowed=[
      "concise", "detailed", "auto",
    ]),
    Some("detailed"),
  )
  assert_eq(reader.take_bool("enabled"), None)
  json_inspect(reader.remaining_values(), content={
    "extension": { "mode": "fast" },
  })
  assert_eq(reader.diagnostics().length(), 2)
  assert_true(reader.diagnostics()[0] is @provider.Deprecated(..))
  assert_true(reader.diagnostics()[1] is @provider.Compatibility(..))
}

///|
test "typed provider option reader rejects fractional integers" {
  assert_eq(json_number_as_int(1024.5), None)
  let reader = ProviderOptionsReader::new(
    resolve_provider_options(
      { "localTest": { "count": 3.5 } },
      provider_name="local-test.chat",
    ),
  )
  assert_eq(reader.take_int("count"), None)
  assert_eq(reader.diagnostics().length(), 1)
  assert_true(
    reader.diagnostics()[0]
    is @provider.Compatibility(feature="providerOptions.count", ..),
  )
}

///|
test "provider metadata key follows the selected camel-case namespace" {
  assert_eq(
    resolve_provider_options_key("local-test.chat", {
      "localTest": { "user": "caller" },
    }),
    "localTest",
  )
  assert_eq(
    resolve_provider_options_key("local-test.chat", {
      "local-test": { "user": "caller" },
    }),
    "local-test",
  )
  assert_eq(
    resolve_provider_options_key("local-test.chat", Map([])),
    "local-test",
  )
  assert_eq(
    resolve_provider_options_key(" anthropic.beta.responses ", Map([])),
    "anthropic",
  )
}

///|
test "provider options use the leading provider segment" {
  let resolution = resolve_provider_options(
    { "anthropic": { "thinking": { "type": "adaptive" } } },
    provider_name="anthropic.beta.messages",
  )
  assert_eq(resolution.namespace_key, Some("anthropic"))
  json_inspect(resolution.values, content={ "thinking": { "type": "adaptive" } })
}

///|
test "append_path normalizes one trailing slash and avoids duplicates" {
  assert_eq(
    append_path("https://example.com/v1/", "/responses"),
    "https://example.com/v1/responses",
  )
  assert_eq(
    append_path("https://example.com/v1/responses", "responses"),
    "https://example.com/v1/responses",
  )
}

///|
test "AI SDK-style URL helper preserves optional endpoints" {
  assert_eq(
    withoutTrailingSlash(Some("https://example.com/v1/")),
    Some("https://example.com/v1"),
  )
  assert_eq(withoutTrailingSlash(None), None)
}

///|
test "WebSocket URL conversion preserves WebSocket URLs" {
  assert_eq(
    to_websocket_url("https://example.com/v1/realtime"),
    "wss://example.com/v1/realtime",
  )
  assert_eq(
    toWebSocketUrl("http://example.com/socket"),
    "ws://example.com/socket",
  )
  assert_eq(
    to_websocket_url("wss://example.com/socket"),
    "wss://example.com/socket",
  )
}

///|
async test "native WebSocket connector sends protocols and exchanges text" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, _, connection) => {
          assert_eq(
            request.headers.get("sec-websocket-protocol"),
            Some("realtime, protocol-token"),
          )
          assert_eq(request.headers.get("x-provider"), Some("moonai"))
          let websocket = @websocket.from_http_server(request, connection)
          defer websocket.close()
          let message = websocket.recv()
          assert_true(message.kind is @websocket.Text)
          assert_eq(message.read_all().text(), "hello")
          websocket.send_text("world")
          websocket.send_close()
        },
        max_connections=1,
      )
    }
    let connector = native_websocket_connector()
    let websocket = connector.connect(
      "ws://127.0.0.1:\{server.addr.port()}/translation",
      ["realtime", "protocol-token"],
      { "X-Provider": "moonai" },
    )
    defer websocket.close()
    websocket.send_text("hello")
    assert_eq(websocket.receive(), WebSocketText("world"))
    assert_true(websocket.receive() is WebSocketClosed(code=Some(1000), ..))
  }
}

///|
test "JSON field accessors reject mismatched values" {
  let value : Json = { "name": "moonai", "count": 3, "enabled": true }
  assert_eq(json_string_field(value, "name"), Some("moonai"))
  assert_eq(json_string_field(value, "enabled"), None)
  assert_eq(json_int_field_opt(value, "count"), Some(3))
  assert_eq(json_int_field(value, "missing", default=7), 7)
}

///|
test "provider metadata preserves gateway provider keys" {
  let value : Json = {
    "provider_metadata": { "openai": { "trace_id": "trace-1" } },
  }
  let metadata = provider_metadata_from_json(value, "openai.chat")
  json_inspect(metadata["openai"], content={ "trace_id": "trace-1" })
}

///|
test "provider utils resolves shared provider references" {
  let reference = @provider.ProviderReference::single(
    provider="openai",
    id="file-123",
  )
  assert_eq(resolve_provider_reference(reference, "openai"), "file-123")
  assert_eq(resolveProviderReference(reference, "openai"), "file-123")
}

///|
test "media type helpers resolve full and top-level-only inputs" {
  assert_eq(get_top_level_media_type("image/png"), "image")
  assert_eq(is_full_media_type("image/png"), true)
  assert_eq(is_full_media_type("image/*"), false)
  assert_eq(resolve_full_media_type("image", "iVBORw0KGgo="), "image/png")
  assert_eq(
    resolve_full_media_type("application", "JVBERg=="),
    "application/pdf",
  )
  assert_eq(decode_base64_text("TW9vbkJpdA=="), "MoonBit")
  assert_eq(getTopLevelMediaType("image/png"), "image")
  assert_eq(isFullMediaType("image/png"), true)
  assert_eq(resolveFullMediaType("image", "iVBORw0KGgo="), "image/png")
  assert_eq(mediaTypeToExtension("audio/mpeg"), "mp3")
}

///|
test "media type detection skips bounded ID3v2 tags and accepts base64url" {
  assert_eq(
    detect_media_type("SUQzBAAAAAAABQAAAAAA//s=", top_level_type="audio"),
    Some("audio/mpeg"),
  )
  assert_eq(resolve_full_media_type("image/*", "iVBORw0KGgo"), "image/png")
  assert_eq(
    detectMediaType("SUQzBAAAAAAABQAAAAAA//s=", top_level_type="audio"),
    Some("audio/mpeg"),
  )
}

///|
test "multipart form data preserves binary files and redacts diagnostics" {
  let form = encode_multipart_form_data(
    [
      MultipartField::text(name="model", value="gpt-image-1"),
      MultipartField::file(
        name="image",
        filename="input.png",
        media_type="image/png",
        data=b"PNG-DATA",
      ),
    ],
    boundary="test-boundary",
  )
  assert_eq(form.content_type, "multipart/form-data; boundary=test-boundary")
  let body = @utf8.decode(form.body)
  assert_true(body.contains("name=\"model\"\r\n\r\ngpt-image-1"))
  assert_true(body.contains("filename=\"input.png\""))
  assert_true(body.contains("Content-Type: image/png\r\n\r\nPNG-DATA"))
  assert_true(body.has_suffix("--test-boundary--\r\n"))
  assert_true(form.diagnostic_body.contains("bytes=8"))
  assert_true(!form.diagnostic_body.contains("PNG-DATA"))
}

///|
test "multipart form data rejects header injection" {
  try
    encode_multipart_form_data([
      MultipartField::text(name="bad\r\nheader", value="value"),
    ])
  catch {
    Failure::Failure(message) => assert_true(message.contains("invalid header"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an invalid multipart field name")
  }
}

///|
test "multipart form data extends colliding boundaries" {
  let form = encode_multipart_form_data(
    [
      MultipartField::file(
        name="image",
        filename="input.png",
        media_type="image/png",
        data=b"prefix-test-boundary-suffix",
      ),
    ],
    boundary="test-boundary",
  )
  assert_eq(form.boundary, "test-boundaryx")
  assert_true(form.content_type.has_suffix("test-boundaryx"))
}

///|
async test "V4 image files resolve without legacy image conversion" {
  let bytes = resolve_image_model_v4_file(
    @provider.ImageModelV4File::bytes(data=b"raw-image", media_type="image/png"),
    filename="input.png",
    provider_name="test",
  )
  assert_eq(bytes.filename, "input.png")
  assert_eq(bytes.media_type, "image/png")
  assert_eq(bytes.data, b"raw-image")
  let base64 = resolve_image_model_v4_file(
    @provider.ImageModelV4File::base64(
      data="iVBORw0KGgo=",
      media_type="image/*",
    ),
    provider_name="test",
  )
  assert_eq(base64.filename, "image")
  assert_eq(base64.media_type, "image/png")
  assert_eq(base64.data, b"\x89PNG\r\n\x1a\n")
}

///|
fn assert_resolved_download_blocked(
  hostname : String,
  address : String,
) -> Unit raise {
  try
    validate_resolved_download_address(hostname, @socket.Addr::parse(address))
  catch {
    DownloadError(url~, message~, ..) => {
      assert_eq(url, hostname)
      assert_true(message.contains("resolved to disallowed IP address"))
      return
    }
    error =>
      fail("unexpected resolved-address error: \{@debug.to_string(error)}")
  } noraise {
    _ => fail("expected resolved address to be blocked: \{address}")
  }
}

///|
test "safe download validates the exact resolved address" {
  validate_resolved_download_address(
    "files.example.com",
    @socket.Addr::parse("8.8.8.8:443"),
  )
  validate_resolved_download_address(
    "files.example.com",
    @socket.Addr::parse("[2606:4700:4700::1111]:443"),
  )
  assert_resolved_download_blocked("files.example.com", "127.0.0.1:443")
  assert_resolved_download_blocked("files.example.com", "169.254.169.254:443")
  assert_resolved_download_blocked("files.example.com", "[::1]:443")
  assert_resolved_download_blocked("files.example.com", "[fc00::1]:443")
}

///|
async test "safe download pins the connection while preserving Host and request target" {
  @async.with_task_group() <| group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let address = server.addr
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_until("\r\n\r\n").unwrap_or("")
      assert_true(request.has_prefix("GET /asset?download=1 HTTP/1.1\r\n"))
      assert_true(
        request.contains("Host: files.example.test:\{address.port()}\r\n"),
      )
      assert_true(request.contains("Authorization: Bearer test\r\n"))
      assert_true(request.contains("Accept-Encoding: identity\r\n"))
      connection.write(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 7\r\nConnection: close\r\n\r\nMoonBit",
      )
    }
    let url = "http://files.example.test:\{address.port()}/asset?download=1#ignored"
    let request = HttpRequest::get(url~, headers={
      "Authorization": "Bearer test",
      "Accept-Encoding": "gzip",
    })
    let response = safe_native_download_fetch_at(
      request,
      safe_download_target(url),
      address,
      1024L,
    )
    assert_eq(response.status_code, 200)
    assert_eq(response.headers.get("content-type"), Some("text/plain"))
    assert_eq(response.body, b"MoonBit")
  }
}

///|
async test "safe download decodes chunked bodies and trailers" {
  @async.with_task_group() <| group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let address = server.addr
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      connection.read_until("\r\n\r\n") |> ignore
      connection.write(
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n4\r\nMoon\r\n3;source=test\r\nBit\r\n0\r\nX-Trace: done\r\n\r\n",
      )
    }
    let url = "http://cdn.example.test:\{address.port()}/chunked"
    let response = safe_native_download_fetch_at(
      HttpRequest::get(url~),
      safe_download_target(url),
      address,
      1024L,
    )
    assert_eq(response.body, b"MoonBit")
  }
}

///|
async test "safe download handles duplicate and conflicting Content-Length headers" {
  @async.with_task_group() <| group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let address = server.addr
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      connection.read_until("\r\n\r\n") |> ignore
      connection.write(
        "HTTP/1.1 200 OK\r\nContent-Length: 7\r\nContent-Length: 7\r\nConnection: close\r\n\r\nMoonBit",
      )
    }
    let url = "http://cdn.example.test:\{address.port()}/duplicate-length"
    let response = safe_native_download_fetch_at(
      HttpRequest::get(url~),
      safe_download_target(url),
      address,
      1024L,
    )
    assert_eq(response.body, b"MoonBit")
  }
  @async.with_task_group() <| group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let address = server.addr
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      connection.read_until("\r\n\r\n") |> ignore
      connection.write(
        "HTTP/1.1 200 OK\r\nContent-Length: 7\r\nContent-Length: 8\r\nConnection: close\r\n\r\nMoonBit",
      )
    }
    let url = "http://cdn.example.test:\{address.port()}/conflicting-length"
    try
      safe_native_download_fetch_at(
        HttpRequest::get(url~),
        safe_download_target(url),
        address,
        1024L,
      )
      |> ignore
    catch {
      DownloadError(message~, ..) => {
        assert_true(message.contains("conflicting Content-Length"))
        return
      }
      error => fail("unexpected framing error: \{@debug.to_string(error)}")
    } noraise {
      _ => fail("expected conflicting Content-Length headers to fail")
    }
  }
}

///|
async test "safe download skips informational responses and reads HTTP 1.0 to close" {
  @async.with_task_group() <| group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let address = server.addr
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      connection.read_until("\r\n\r\n") |> ignore
      connection.write(
        "HTTP/1.1 103 Early Hints\r\nLink: </asset>; rel=preload\r\n\r\nHTTP/1.0 200 OK\r\nContent-Type: text/plain\r\n\r\nMoonBit",
      )
    }
    let url = "http://cdn.example.test:\{address.port()}/http-1-0"
    let response = safe_native_download_fetch_at(
      HttpRequest::get(url~),
      safe_download_target(url),
      address,
      1024L,
    )
    assert_eq(response.status_code, 200)
    assert_eq(response.body, b"MoonBit")
  }
}

///|
async test "safe download rejects oversized bodies before buffering them" {
  @async.with_task_group() <| group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let address = server.addr
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      connection.read_until("\r\n\r\n") |> ignore
      connection.write(
        "HTTP/1.1 200 OK\r\nContent-Length: 7\r\nConnection: close\r\n\r\nMoonBit",
      )
    }
    let url = "http://cdn.example.test:\{address.port()}/large"
    try
      safe_native_download_fetch_at(
        HttpRequest::get(url~),
        safe_download_target(url),
        address,
        4L,
      )
      |> ignore
    catch {
      DownloadError(message~, ..) => {
        assert_true(message.contains("Content-Length: 7"))
        return
      }
      error => fail("unexpected size-limit error: \{@debug.to_string(error)}")
    } noraise {
      _ => fail("expected oversized safe download to fail")
    }
  }
}

///|
test "safe download rejects request header injection" {
  let url = "https://files.example.com/file"
  try
    safe_download_request_text(
      HttpRequest::get(url~, headers={ "X-Test": "ok\r\nX-Injected: true" }),
      safe_download_target(url),
    )
    |> ignore
  catch {
    DownloadError(..) => ()
  } noraise {
    _ => fail("expected injected header to be rejected")
  }
}

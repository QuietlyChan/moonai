///|
priv struct ScriptedUploadStream {
  chunks : Array[Bytes]
  next : Ref[Int]
}

///|
fn ScriptedUploadStream::new(chunks : Array[Bytes]) -> ScriptedUploadStream {
  { chunks, next: Ref(0), }
}

///|
impl @provider.UploadByteStream for ScriptedUploadStream with fn read_chunk(
  self,
) -> Bytes? {
  if self.next.val < self.chunks.length() {
    let chunk = self.chunks[self.next.val]
    self.next.val = self.next.val + 1
    Some(chunk)
  } else {
    None
  }
}

///|
impl @provider.UploadByteStream for ScriptedUploadStream with fn size_hint_bytes(
  self,
) -> Int64? {
  let mut total = 0L
  for chunk in self.chunks {
    total = total + chunk.length().to_int64()
  }
  Some(total)
}

///|
fn streaming_test_fields(
  stream : &@provider.UploadByteStream,
) -> Array[@provider_utils.MultipartFieldPlan] {
  [
    @provider_utils.MultipartPlanText(name="purpose", value="user_data"),
    @provider_utils.MultipartPlanBytes(
      name="meta",
      filename="meta.txt",
      media_type="text/plain",
      data=@utf8.encode("hello"),
    ),
    @provider_utils.MultipartPlanStream(
      name="payload",
      filename="video.bin",
      media_type="video/mp4",
      stream~,
    ),
    @provider_utils.MultipartPlanText(name="note", value="done"),
  ]
}

///|
fn buffered_equivalent_fields(
  stream_bytes : Bytes,
) -> Array[@provider_utils.MultipartField] {
  [
    @provider_utils.MultipartField::text(name="purpose", value="user_data"),
    @provider_utils.MultipartField::file(
      name="meta",
      filename="meta.txt",
      media_type="text/plain",
      data=@utf8.encode("hello"),
    ),
    @provider_utils.MultipartField::file(
      name="payload",
      filename="video.bin",
      media_type="video/mp4",
      data=stream_bytes,
    ),
    @provider_utils.MultipartField::text(name="note", value="done"),
  ]
}

///|
const STREAMING_TEST_BOUNDARY : String = "moonai-test-boundary"

///|
async test "streaming multipart upload reassembles the buffered body" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let received_body : Ref[Bytes] = Ref(b"")
    let received_length : Ref[Int] = Ref(0)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, connection) => {
          received_body.val = body.read_all().binary()
          received_length.val = received_body.val.length()
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write("{\"ok\":true}")
        },
        max_connections=1,
      )
    }
    let chunk_one = @utf8.encode("first-chunk;")
    let chunk_two = @utf8.encode("second chunk with spaces")
    let stream = ScriptedUploadStream::new([chunk_one, chunk_two])
    let mut stream_bytes : Bytes = b""
    for chunk in [chunk_one, chunk_two] {
      stream_bytes = stream_bytes + chunk
    }
    let plan = plan_multipart_streaming(
      streaming_test_fields(stream),
      boundary=STREAMING_TEST_BOUNDARY,
    )
    // The plan matches the fully buffered encoding byte for byte.
    let buffered = encode_multipart_form_data(
      buffered_equivalent_fields(stream_bytes),
      boundary=STREAMING_TEST_BOUNDARY,
    )
    assert_eq(plan.content_length, buffered.body.length().to_int64())
    let response = post_multipart_streaming(
      url="http://127.0.0.1:\{server.addr.port()}/upload",
      headers=Map([]),
      plan~,
      transport=@provider_utils.native_streaming_body_transport(),
    )
    assert_eq(response.value, { "ok": true })
    // The server received the exact buffered body, streamed incrementally.
    assert_eq(received_length.val, buffered.body.length())
    assert_eq(received_body.val, buffered.body)
    assert_true(response.request.body.contains("filename=\"video.bin\""))
  }
}

///|
test "streaming multipart plans require exactly one sized stream" {
  let stream = ScriptedUploadStream::new([@utf8.encode("x")])
  let plan = plan_multipart_streaming(
    streaming_test_fields(stream),
    boundary=STREAMING_TEST_BOUNDARY,
  )
  assert_true(plan.diagnostic_body.contains("<stream>"))
  assert_true(!plan.diagnostic_body.contains("second chunk"))
  // The streamed payload never lands in the diagnostic body.
  assert_true(plan.diagnostic_body.contains("purpose"))
}

///|
priv struct UnsizedUploadStream {
  chunks : Array[Bytes]
  next : Ref[Int]
}

///|
fn UnsizedUploadStream::new(chunks : Array[Bytes]) -> UnsizedUploadStream {
  { chunks, next: Ref(0), }
}

///|
impl @provider.UploadByteStream for UnsizedUploadStream with fn read_chunk(self) -> Bytes? {
  if self.next.val < self.chunks.length() {
    let chunk = self.chunks[self.next.val]
    self.next.val = self.next.val + 1
    Some(chunk)
  } else {
    None
  }
}

///|
impl @provider.UploadByteStream for UnsizedUploadStream with fn size_hint_bytes(
  _self,
) -> Int64? {
  None
}

///|
test "streaming multipart plans reject unsized streams" {
  let stream = UnsizedUploadStream::new([@utf8.encode("x")])
  let outcome = try {
    let _ = plan_multipart_streaming(
      streaming_test_fields(stream),
      boundary=STREAMING_TEST_BOUNDARY,
    )
    None
  } catch {
    _ => Some(())
  }
  assert_true(outcome is Some(_))
}

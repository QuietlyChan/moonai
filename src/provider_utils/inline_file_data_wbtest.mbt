///|
priv struct ChunkStream {
  chunks : Array[Bytes]
  mut index : Int
}

///|
fn ChunkStream::new(chunks : Array[Bytes]) -> ChunkStream {
  { chunks, index: 0, }
}

///|
impl @provider.UploadByteStream for ChunkStream with fn read_chunk(self) -> Bytes? {
  if self.index < self.chunks.length() {
    let chunk = self.chunks[self.index]
    self.index = self.index + 1
    Some(chunk)
  } else {
    None
  }
}

///|
impl @provider.UploadByteStream for ChunkStream with fn size_hint_bytes(self) -> Int64? {
  let mut total = 0L
  for chunk in self.chunks {
    total = total + chunk.length().to_int64()
  }
  Some(total)
}

///|
async test "collect upload file data drains stream chunks in order" {
  let stream = ChunkStream::new([b"Hello, ", b"Moon", b"Bit!"])
  let collected = collect_upload_file_data(
    @provider.UploadFileData::stream(stream),
  )
  assert_eq(collected, @utf8.encode("Hello, MoonBit!"))
}

///|
test "synchronous conversion rejects streaming upload data" {
  let stream = ChunkStream::new([b"ignored"])
  try
    convert_inline_file_data_to_bytes(@provider.UploadFileData::stream(stream))
  catch {
    @provider.UnsupportedFunctionalityError(..) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected an unsupported functionality error")
  }
}

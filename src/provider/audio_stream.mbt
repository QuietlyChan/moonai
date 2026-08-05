///|
/// Audio format shared by streaming audio providers.
pub(all) struct AudioFormat {
  media_type : String
  sample_rate : Int?
} derive(Debug, Eq)

///|
/// Construct an audio format such as `audio/pcm` at 24 kHz.
pub fn AudioFormat::new(
  media_type~ : String,
  sample_rate? : Int,
) -> AudioFormat {
  { media_type, sample_rate }
}

///|
/// One source-audio chunk. Base64 chunks are already encoded and byte chunks
/// are encoded by the provider adapter when required by its wire protocol.
pub(all) enum AudioChunk {
  AudioBytes(Bytes)
  AudioBase64(String)
} derive(Debug, Eq)

///|
/// Construct a raw-byte source-audio chunk.
pub fn AudioChunk::bytes(data : Bytes) -> AudioChunk {
  AudioBytes(data)
}

///|
/// Construct an already Base64-encoded source-audio chunk.
pub fn AudioChunk::base64(data : String) -> AudioChunk {
  AudioBase64(data)
}

///|
/// Pull-based source for live audio. `cancel` lets a provider stop an upstream
/// producer when the remote session finishes or its transport fails.
pub(open) trait AudioStream {
  async fn read_next(Self) -> AudioChunk?
  fn cancel(Self) -> Unit
}

///|
priv struct ChunkAudioStream {
  chunks : Array[AudioChunk]
  index : Ref[Int]
  cancelled : Ref[Bool]
}

///|
impl AudioStream for ChunkAudioStream with fn read_next(self) {
  if self.cancelled.val || self.index.val >= self.chunks.length() {
    return None
  }
  let chunk = self.chunks[self.index.val]
  self.index.val = self.index.val + 1
  Some(chunk)
}

///|
impl AudioStream for ChunkAudioStream with fn cancel(self) {
  self.cancelled.val = true
}

///|
/// Create a finite audio stream. This is useful for buffered recordings and
/// deterministic provider tests.
pub fn audio_chunks(chunks : Array[AudioChunk]) -> &AudioStream {
  ChunkAudioStream::{ chunks, index: Ref(0), cancelled: Ref(false) }
}

///|
priv struct ReaderAudioStream {
  reader : &@io.Reader
  max_chunk_size : Int
  cancelled : Ref[Bool]
}

///|
impl AudioStream for ReaderAudioStream with fn read_next(self) {
  if self.cancelled.val {
    return None
  }
  match self.reader.read_some(max_len=self.max_chunk_size) {
    Some(data) => Some(AudioBytes(data))
    None => None
  }
}

///|
impl AudioStream for ReaderAudioStream with fn cancel(self) {
  self.cancelled.val = true
}

///|
/// Adapt any async byte reader to a live audio stream.
pub fn audio_reader(
  reader : &@io.Reader,
  max_chunk_size? : Int = 65_536,
) -> &AudioStream raise {
  guard max_chunk_size > 0 else {
    fail("audio stream max_chunk_size must be greater than zero")
  }
  ReaderAudioStream::{ reader, max_chunk_size, cancelled: Ref(false) }
}

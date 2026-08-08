///|
/// V4 stream transform over the shared Open Responses protocol decoder.
///
/// The wire decoder owns SSE protocol state; this layer owns the public AI SDK
/// V4 event vocabulary. Keeping both in the protocol package prevents provider
/// packages from repeating stream-event adaptation logic.
pub struct OpenResponsesV4StreamDecoder {
  priv decoder : OpenResponsesStreamDecoder
}

///|
/// Create a V4 decoder for the base Open Responses protocol.
pub fn OpenResponsesV4StreamDecoder::new(
  include_raw_chunks? : Bool = false,
  provider_name? : String = "",
  id_generator? : @provider_utils.IdGenerator,
) -> OpenResponsesV4StreamDecoder {
  {
    decoder: OpenResponsesStreamDecoder::new(
      include_raw_chunks~,
      provider_name~,
      id_generator?,
    ),
  }
}

///|
fn OpenResponsesV4StreamDecoder::v4_batch(
  self : OpenResponsesV4StreamDecoder,
  batch : @provider_utils.SseDecodeBatch[@provider.StreamEvent],
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  for event in batch.events {
    match event {
      @provider.StreamStart | @provider.Warning(_) => ()
      @provider.Finish(..) =>
        events.push(
          @provider.V4Finish(
            usage=self.decoder.v4_usage(),
            reason=self.decoder.v4_finish_reason(),
            provider_metadata=self.decoder.provider_metadata_snapshot(),
          ),
        )
      other =>
        match @provider.LanguageModelV4StreamPart::from_stream_event(other) {
          Some(part) => events.push(part)
          None => ()
        }
    }
  }
  { events, consumed_event: batch.consumed_event, done: batch.done }
}

///|
/// Feed one physical SSE line and return V4 stream parts.
pub fn OpenResponsesV4StreamDecoder::feed_line(
  self : OpenResponsesV4StreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  self.v4_batch(self.decoder.feed_line(raw))
}

///|
/// Flush a final unterminated SSE payload into V4 stream parts.
pub fn OpenResponsesV4StreamDecoder::flush_buffered(
  self : OpenResponsesV4StreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  self.v4_batch(self.decoder.flush_buffered())
}

///|
/// Finish the V4 transform after a normal transport EOF.
pub fn OpenResponsesV4StreamDecoder::finish_stream(
  self : OpenResponsesV4StreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  self.v4_batch(self.decoder.finish_stream())
}

///|
/// Return response identity accumulated from protocol frames.
pub fn OpenResponsesV4StreamDecoder::response_metadata_snapshot(
  self : OpenResponsesV4StreamDecoder,
) -> @provider.ResponseMetadata? {
  self.decoder.response_metadata_snapshot()
}

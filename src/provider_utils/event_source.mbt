///|
/// Provider-neutral result produced by decoding one SSE payload.
pub(all) struct DecodeBatch {
  events : Array[@provider.StreamEvent]
  consumed_event : Bool
  done : Bool
} derive(Debug)

///|
/// Return a batch that did not consume a complete SSE event.
pub fn DecodeBatch::empty(done : Bool) -> DecodeBatch {
  { events: [], consumed_event: false, done }
}

///|
/// Buffer physical Server-Sent Event lines into complete `data:` payloads.
/// Provider decoders own JSON interpretation; this type only implements SSE
/// framing, matching the role of AI SDK's event-source response handler.
pub struct EventSourceBuffer {
  priv data_lines : Array[String]
}

///|
/// Create an empty SSE payload buffer.
pub fn EventSourceBuffer::new() -> EventSourceBuffer {
  { data_lines: [] }
}

///|
fn data_fragment(raw : String) -> String? {
  let line = raw.strip_suffix("\r").unwrap_or(raw)
  if line == "data" {
    Some("")
  } else {
    line
    .strip_prefix("data:")
    .map(data => {
      let value = data.strip_prefix(" ").unwrap_or(data)
      "\{value}"
    })
  }
}

///|
/// Feed one physical SSE line and return a payload when a blank line closes
/// the current event. Comments and non-data fields are ignored.
pub fn EventSourceBuffer::feed_line(
  self : EventSourceBuffer,
  raw : String,
) -> String? {
  if raw.trim().is_empty() {
    self.flush()
  } else {
    if data_fragment(raw) is Some(data) {
      self.data_lines.push(data)
    }
    None
  }
}

///|
/// Flush a final unterminated SSE data event.
pub fn EventSourceBuffer::flush(self : EventSourceBuffer) -> String? {
  guard self.data_lines.length() > 0 else { return None }
  let payload = self.data_lines.join("\n")
  self.data_lines.clear()
  Some(payload)
}

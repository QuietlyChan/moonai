///|
/// Transport-neutral result produced by decoding one SSE payload.
///
/// The transport owns framing, retries, and the stream-start boundary while
/// protocol decoders choose the event vocabulary. In particular, V4 language
/// models can emit `LanguageModelV4StreamPart` directly instead of routing
/// through the older `StreamEvent` contract.
pub(all) struct SseDecodeBatch[E] {
  events : Array[E]
  consumed_event : Bool
  done : Bool
} derive(Debug)

///|
/// Return a generic batch that did not consume a complete SSE event.
pub fn[E] SseDecodeBatch::empty(done : Bool) -> SseDecodeBatch[E] {
  { events: [], consumed_event: false, done }
}

///|
fn empty_sse_lifecycle_callback() -> Unit {
  ()
}

///|
/// Provider-specific policy for deciding when an SSE request has crossed the
/// early-error boundary and may be exposed as a started stream.
///
/// Most providers start on their first complete SSE event and do not need a
/// policy. Providers with a separate acceptance event can keep early frames
/// buffered, retain retry eligibility, and use a short grace window to catch
/// an error flushed together with the acceptance event.
pub struct SseStreamStartPolicy {
  priv is_accepted : () -> Bool
  priv is_output : () -> Bool
  priv accepted_grace_ms : Int
  priv on_started : () -> Unit
  priv on_retry : () -> Unit
}

///|
/// Construct a provider-specific SSE stream-start policy.
pub fn SseStreamStartPolicy::new(
  is_accepted~ : () -> Bool,
  is_output~ : () -> Bool,
  accepted_grace_ms? : Int = 50,
  on_started? : () -> Unit = empty_sse_lifecycle_callback,
  on_retry? : () -> Unit = empty_sse_lifecycle_callback,
) -> SseStreamStartPolicy raise {
  guard accepted_grace_ms >= 0 else {
    fail("SSE accepted grace period must not be negative")
  }
  { is_accepted, is_output, accepted_grace_ms, on_started, on_retry }
}

///|
fn SseStreamStartPolicy::accepted(self : SseStreamStartPolicy) -> Bool {
  (self.is_accepted)()
}

///|
fn SseStreamStartPolicy::output(self : SseStreamStartPolicy) -> Bool {
  (self.is_output)()
}

///|
fn SseStreamStartPolicy::started(self : SseStreamStartPolicy) -> Unit {
  (self.on_started)()
}

///|
fn SseStreamStartPolicy::retry(self : SseStreamStartPolicy) -> Unit {
  (self.on_retry)()
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

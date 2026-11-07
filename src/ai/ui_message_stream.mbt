///|
/// Map a V4 stream part to a UI message chunk (camelCase JSON, the wire
/// shape consumed by chat UIs). Returns None for parts without a UI
/// representation (stream-start, raw, response-metadata).
pub fn ui_message_chunk(part : @provider.LanguageModelV4StreamPart) -> Json? {
  match part {
    @provider.V4TextStart(id~, ..) => Some({ "type": "text-start", "id": id })
    @provider.V4TextDelta(id~, delta~, ..) =>
      Some({ "type": "text-delta", "id": id, "delta": delta })
    @provider.V4TextEnd(id~, ..) => Some({ "type": "text-end", "id": id })
    @provider.V4ReasoningStart(id~, ..) =>
      Some({ "type": "reasoning-start", "id": id })
    @provider.V4ReasoningDelta(id~, delta~, ..) =>
      Some({ "type": "reasoning-delta", "id": id, "delta": delta })
    @provider.V4ReasoningEnd(id~, ..) =>
      Some({ "type": "reasoning-end", "id": id })
    @provider.V4ToolInputStart(id~, tool_name~, ..) =>
      Some({ "type": "tool-input-start", "id": id, "toolName": tool_name })
    @provider.V4ToolInputDelta(id~, delta~, ..) =>
      Some({ "type": "tool-input-delta", "id": id, "delta": delta })
    @provider.V4ToolInputEnd(id~, ..) =>
      Some({ "type": "tool-input-end", "id": id })
    @provider.V4ToolCallReady(call) =>
      Some({
        "type": "tool-call",
        "toolCallId": call.tool_call_id,
        "toolName": call.tool_name,
        "input": call.input,
      })
    @provider.V4Finish(reason~, ..) =>
      Some({
        "type": "finish",
        "finishReason": match reason.unified {
          @provider.V4FinishStop => "stop"
          @provider.V4FinishLength => "length"
          @provider.V4FinishContentFilter => "content-filter"
          @provider.V4FinishToolCalls => "tool-calls"
          @provider.V4FinishError => "error"
          @provider.V4FinishOther => "other"
        },
      })
    _ => None
  }
}

///|
/// Build the UI message chunk sequence for a completed assistant reply:
/// one text block plus tool-call chunks and a terminating finish chunk.
pub fn ui_chunks_from_text(
  text~ : String,
  tool_calls~ : Array[@provider.ToolCall],
) -> Array[Json] {
  let chunks : Array[Json] = []
  chunks.push({ "type": "text-start", "id": "text-0" })
  if text != "" {
    chunks.push({ "type": "text-delta", "id": "text-0", "delta": text })
  }
  chunks.push({ "type": "text-end", "id": "text-0" })
  for call in tool_calls {
    chunks.push({
      "type": "tool-call",
      "toolCallId": call.id,
      "toolName": call.name,
      "input": call.arguments,
    })
  }
  chunks.push({ "type": "finish", "finishReason": "stop" })
  chunks
}

///|
/// An accumulating UI message stream sink: chunks are enqueued and encoded
/// as server-sent-event frames (`data: {json}\n\n`), the wire format the
/// upstream `createUIMessageStreamResponse` emits.
pub struct UiMessageStream {
  priv chunks : Array[Json]
  priv mut closed : Bool
}

///|
/// Create an empty UI message stream.
pub fn UiMessageStream::new() -> UiMessageStream {
  { chunks: [], closed: false, }
}

///|
/// Enqueue a chunk. Enqueueing after close is ignored.
pub fn UiMessageStream::enqueue(self : UiMessageStream, chunk : Json) -> Unit {
  if !self.closed {
    self.chunks.push(chunk)
  }
}

///|
/// Close the stream: subsequent enqueues are ignored.
pub fn UiMessageStream::close(self : UiMessageStream) -> Unit {
  self.closed = true
}

///|
/// Number of enqueued chunks.
pub fn UiMessageStream::length(self : UiMessageStream) -> Int32 {
  self.chunks.length()
}

///|
/// The enqueued chunks in order.
pub fn UiMessageStream::to_chunks(self : UiMessageStream) -> Array[Json] {
  self.chunks.copy()
}

///|
/// Encode the stream as SSE frames: one `data: {json}\n\n` block per chunk.
pub fn UiMessageStream::to_sse(self : UiMessageStream) -> String {
  let builder = StringBuilder()
  for chunk in self.chunks {
    builder.write_string("data: ")
    builder.write_string(chunk.stringify())
    builder.write_string("\n\n")
  }
  builder.to_string()
}

///|
/// Map a V4 stream part to a UI message chunk (camelCase JSON, the shape
/// consumed by chat UIs). Returns None for parts with no UI representation.
pub fn workflow_ui_message_chunk(
  part : @provider.LanguageModelV4StreamPart,
) -> Json? {
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
        "finishReason": workflow_finish_reason_name(reason.unified),
      })
    _ => None
  }
}

///|
fn workflow_finish_reason_name(
  unified : @provider.LanguageModelV4UnifiedFinishReason,
) -> String {
  match unified {
    @provider.V4FinishStop => "stop"
    @provider.V4FinishLength => "length"
    @provider.V4FinishContentFilter => "content-filter"
    @provider.V4FinishToolCalls => "tool-calls"
    @provider.V4FinishError => "error"
    @provider.V4FinishOther => "other"
  }
}

///|
/// Build the UI message chunk stream for a completed workflow run: one text
/// block for the assistant reply, tool-call chunks for each call, and a
/// terminating finish chunk. Chunks are indexed sequentially (`startIndex`/
/// `endIndex` semantics match the upstream UI message stream).
pub fn workflow_ui_chunks_from_text(
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

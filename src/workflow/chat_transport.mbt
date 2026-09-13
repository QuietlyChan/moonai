///|
/// In-process chat transport for workflow agents. The upstream transport
/// posts UI messages to a workflow HTTP endpoint and resumes interrupted
/// streams; the native equivalent drives a `WorkflowAgent` directly, emits
/// the reply as a UI message chunk stream, and persists the snapshot so a
/// later `reconnect_to_stream` can replay the chunk sequence.
pub struct WorkflowChatTransport {
  priv agent : WorkflowAgent
}

///|
/// The response of one transport send: the UI chunk stream plus the
/// persisted snapshot to store alongside the chat.
pub(all) struct WorkflowChatResponse {
  chunks : Array[Json]
  snapshot : Json
  steps : Int
} derive(Debug)

///|
/// Wrap a workflow agent as a chat transport.
pub fn WorkflowChatTransport::new(
  agent~ : WorkflowAgent,
) -> WorkflowChatTransport {
  WorkflowChatTransport::{ agent, }
}

///|
/// Send the user prompt: runs one workflow turn and returns the UI chunk
/// stream for the assistant reply.
pub async fn WorkflowChatTransport::send_messages(
  self : WorkflowChatTransport,
  prompt~ : String,
) -> WorkflowChatResponse {
  let result = self.agent.generate(
    options=@agent.AgentCallOptions::new(prompt~),
  )
  let tool_calls : Array[@provider.ToolCall] = []
  for call in result.snapshot.messages {
    for tool_call in call.tool_calls {
      tool_calls.push(
        @provider.ToolCall::new(
          id=tool_call.id,
          name=tool_call.name,
          arguments=tool_call.input.stringify(),
        ),
      )
    }
  }
  WorkflowChatResponse::{
    chunks: workflow_ui_chunks_from_text(text=result.text, tool_calls~),
    snapshot: workflow_snapshot_to_json(snapshot=result.snapshot),
    steps: result.steps,
  }
}

///|
/// Reconnect to an interrupted stream: replays the UI chunk sequence derived
/// from the persisted snapshot, continuing the chunk index where the stored
/// stream left off (upstream resume semantics). The reply is re-emitted in
/// full — clients deduplicate by chunk index.
pub fn WorkflowChatTransport::reconnect_to_stream(
  _self : WorkflowChatTransport,
  snapshot_json~ : Json,
) -> Array[Json] raise {
  let snapshot = workflow_snapshot_from_json(value=snapshot_json)
  let chunks : Array[Json] = []
  let mut index = 0
  for message in snapshot.messages {
    match message.role {
      @provider_utils.ModelAssistant => {
        chunks.push({ "type": "text-start", "id": "text-\{index}" })
        if message.content != "" {
          chunks.push({
            "type": "text-delta",
            "id": "text-\{index}",
            "delta": message.content,
          })
        }
        chunks.push({ "type": "text-end", "id": "text-\{index}" })
        index = index + 1
      }
      _ => ()
    }
  }
  chunks.push({ "type": "finish", "finishReason": "stop" })
  chunks
}

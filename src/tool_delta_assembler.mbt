///|
/// One provider delta for a streamed function call.
pub(all) struct ToolCallDelta {
  index : Int
  id : String?
  name : String?
  arguments_delta : String?
} derive(Debug, Eq)

///|
/// Construct one tool-call delta.
pub fn ToolCallDelta::new(
  index~ : Int,
  id? : String,
  name? : String,
  arguments_delta? : String,
) -> ToolCallDelta {
  { index, id, name, arguments_delta }
}

///|
/// Information returned after applying a delta.
pub(all) struct AppliedToolCallDelta {
  index : Int
  stream_id : String
  tool_name : String
  started : Bool
  arguments_delta : String
} derive(Debug, Eq)

///|
/// Reassembles interleaved OpenAI-style tool call deltas by call index.
pub struct ToolCallDeltaAssembler {
  priv stream_ids : Array[String]
  priv ids : Array[String]
  priv names : Array[String]
  priv arguments : Array[StringBuilder]
  priv received : Array[Bool]
}

///|
/// Create an empty assembler.
pub fn ToolCallDeltaAssembler::new() -> ToolCallDeltaAssembler {
  { stream_ids: [], ids: [], names: [], arguments: [], received: [] }
}

///|
fn ToolCallDeltaAssembler::ensure(
  self : ToolCallDeltaAssembler,
  index : Int,
) -> Bool {
  while self.ids.length() <= index {
    let next = self.ids.length()
    self.stream_ids.push("tool-\{next}")
    self.ids.push("")
    self.names.push("")
    self.arguments.push(StringBuilder::new())
    self.received.push(false)
  }
  !self.received[index]
}

///|
/// Apply a delta and return the normalized stream identity and payload.
pub fn ToolCallDeltaAssembler::apply(
  self : ToolCallDeltaAssembler,
  delta : ToolCallDelta,
) -> AppliedToolCallDelta raise {
  guard delta.index >= 0 else { fail("tool call index must be non-negative") }
  let pristine = self.ensure(delta.index)
  self.received[delta.index] = true
  if delta.id is Some(id) && id != "" {
    self.ids[delta.index] = id
    if pristine {
      self.stream_ids[delta.index] = id
    }
  }
  if delta.name is Some(name) && name != "" {
    self.names[delta.index] = name
  }
  let arguments_delta = delta.arguments_delta.unwrap_or("")
  if arguments_delta != "" {
    self.arguments[delta.index].write_string(arguments_delta)
  }
  {
    index: delta.index,
    stream_id: self.stream_ids[delta.index],
    tool_name: self.names[delta.index],
    started: pristine,
    arguments_delta,
  }
}

///|
/// Return complete calls ordered by provider index.
pub fn ToolCallDeltaAssembler::calls(
  self : ToolCallDeltaAssembler,
) -> Array[ToolCall] {
  let result : Array[ToolCall] = []
  for index in 0..<self.ids.length() {
    let id = if self.ids[index] == "" {
      self.stream_ids[index]
    } else {
      self.ids[index]
    }
    result.push(
      ToolCall::new(
        id~,
        name=self.names[index],
        arguments=self.arguments[index].to_string(),
      ),
    )
  }
  result
}

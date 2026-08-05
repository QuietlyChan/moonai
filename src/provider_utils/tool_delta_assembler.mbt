///|
/// One provider delta for a streamed function call.
pub(all) struct ToolCallDelta {
  index : Int
  id : String?
  name : String?
  arguments_delta : String?
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct one tool-call delta.
pub fn ToolCallDelta::new(
  index~ : Int,
  id? : String,
  name? : String,
  arguments_delta? : String,
  provider_metadata? : Map[String, Json] = Map([]),
) -> ToolCallDelta {
  { index, id, name, arguments_delta, provider_metadata }
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
  priv provider_metadata : Array[Map[String, Json]]
  priv received : Array[Bool]
  priv generate_id : IdGenerator
}

///|
/// Create an empty assembler.
///
/// The optional generator is used when a provider omits a tool-call id. This
/// keeps the stream identity stable while matching AI SDK's fallback ID
/// behavior and makes deterministic provider tests possible.
pub fn ToolCallDeltaAssembler::new(
  id_generator? : IdGenerator,
) -> ToolCallDeltaAssembler {
  {
    stream_ids: [],
    ids: [],
    names: [],
    arguments: [],
    provider_metadata: [],
    received: [],
    generate_id: id_generator.unwrap_or(generate_id),
  }
}

///|
fn ToolCallDeltaAssembler::ensure(
  self : ToolCallDeltaAssembler,
  index : Int,
) -> Bool {
  while self.ids.length() <= index {
    let next = self.ids.length()
    // Generate the fallback once, when the stream slot is first observed.
    // A later provider id must not rewrite an already-emitted stream id.
    let fallback_id = (self.generate_id)()
    self.stream_ids.push(
      if fallback_id == "" {
        "tool-\{next}"
      } else {
        fallback_id
      },
    )
    self.ids.push("")
    self.names.push("")
    self.arguments.push(StringBuilder::new())
    self.provider_metadata.push(Map([]))
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
  self.provider_metadata[delta.index] = @provider.merge_provider_metadata(
    self.provider_metadata[delta.index],
    delta.provider_metadata,
  )
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
) -> Array[@provider.ToolCall] {
  let result : Array[@provider.ToolCall] = []
  for index in 0..<self.ids.length() {
    let id = if self.ids[index] == "" {
      self.stream_ids[index]
    } else {
      self.ids[index]
    }
    result.push(
      @provider.ToolCall::new(
        id~,
        name=self.names[index],
        arguments=self.arguments[index].to_string(),
        provider_metadata=self.provider_metadata[index],
      ),
    )
  }
  result
}

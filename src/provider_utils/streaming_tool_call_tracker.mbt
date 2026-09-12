///|
/// Minimal normalized shape for one streamed OpenAI-style tool-call delta.
pub(all) struct StreamingToolCallDelta {
  index : Int?
  id : String?
  tool_type : String?
  function_name : String?
  arguments_delta : String?
  provider_metadata : Map[String, Json]
  data : Json
} derive(Debug, Eq)

///|
/// Construct one normalized streaming tool-call delta.
pub fn StreamingToolCallDelta::new(
  index? : Int,
  id? : String,
  tool_type? : String,
  function_name? : String,
  arguments_delta? : String,
  provider_metadata? : Map[String, Json] = Map([]),
  data? : Json = Json::empty_object(),
) -> StreamingToolCallDelta {
  {
    index,
    id,
    tool_type,
    function_name,
    arguments_delta,
    provider_metadata,
    data,
  }
}

///|
/// Controls validation of the optional OpenAI `type` discriminator.
pub(all) enum StreamingToolCallTypeValidation {
  NoToolCallTypeValidation
  ValidateToolCallTypeIfPresent
  RequireFunctionToolCallType
} derive(Debug, Eq)

///|
/// Provider-neutral lifecycle produced by the shared tracker state machine.
priv enum StreamingToolCallLifecycleEvent {
  StreamingToolInputStart(id~ : String, tool_name~ : String)
  StreamingToolInputDelta(id~ : String, delta~ : String)
  StreamingToolInputEnd(String)
  StreamingToolCallReady(@provider.ToolCall)
}

///|
fn StreamingToolCallLifecycleEvent::to_stream_event(
  self : StreamingToolCallLifecycleEvent,
) -> @provider.StreamEvent {
  match self {
    StreamingToolInputStart(id~, tool_name~) =>
      @provider.ToolInputStart(id~, tool_name~)
    StreamingToolInputDelta(id~, delta~) =>
      @provider.ToolInputDelta(id~, delta~)
    StreamingToolInputEnd(id) => @provider.ToolInputEnd(id)
    StreamingToolCallReady(call) => @provider.ToolCallReady(call)
  }
}

///|
fn StreamingToolCallLifecycleEvent::to_v4_stream_part(
  self : StreamingToolCallLifecycleEvent,
) -> @provider.LanguageModelV4StreamPart {
  match self {
    StreamingToolInputStart(id~, tool_name~) =>
      @provider.V4ToolInputStart(
        id~,
        tool_name~,
        provider_executed=false,
        dynamic=false,
        title=None,
        provider_metadata=Map([]),
      )
    StreamingToolInputDelta(id~, delta~) =>
      @provider.V4ToolInputDelta(id~, delta~, provider_metadata=Map([]))
    StreamingToolInputEnd(id) =>
      @provider.V4ToolInputEnd(id~, provider_metadata=Map([]))
    StreamingToolCallReady(call) =>
      @provider.V4ToolCallReady(
        @provider.LanguageModelV4ToolCall::from_tool_call(call),
      )
  }
}

///|
/// Extract provider metadata when a tool call is first observed.
pub type StreamingToolCallMetadataExtractor = (StreamingToolCallDelta) -> Map[
  String,
  Json,
]

///|
/// Build the provider metadata attached to the final tool-call event.
pub type StreamingToolCallMetadataBuilder = (Map[String, Json]) -> Map[
  String,
  Json,
]

///|
priv struct TrackedStreamingToolCall {
  id : String
  name : String
  arguments : StringBuilder
  metadata : Map[String, Json]
  mut has_finished : Bool
  mut final_call : @provider.ToolCall?
}

///|
/// Tracks interleaved streaming tool calls and owns their stream lifecycle.
///
/// Lookup prefers a non-empty id, falls back to the explicit index, and
/// finally to the most recently seen call; this keeps providers that omit
/// indexes (or rotate ids) from splitting one call into many.
///
/// A complete-looking JSON prefix is never finalized early. All unfinished
/// calls emit `ToolInputEnd` followed by `ToolCallReady` only from `flush`.
pub struct StreamingToolCallTracker {
  priv calls : Array[TrackedStreamingToolCall]
  priv calls_by_id : Map[String, TrackedStreamingToolCall]
  priv calls_by_index : Map[Int, TrackedStreamingToolCall]
  priv mut latest_call : TrackedStreamingToolCall?
  priv generate_id : IdGenerator
  priv type_validation : StreamingToolCallTypeValidation
  priv extract_metadata : StreamingToolCallMetadataExtractor
  priv build_tool_call_provider_metadata : StreamingToolCallMetadataBuilder
}

///|
fn default_streaming_tool_call_metadata(
  delta : StreamingToolCallDelta,
) -> Map[String, Json] {
  delta.provider_metadata
}

///|
fn identity_streaming_tool_call_metadata(
  metadata : Map[String, Json],
) -> Map[String, Json] {
  metadata
}

///|
/// Create an empty streaming tool-call tracker.
pub fn StreamingToolCallTracker::new(
  id_generator? : IdGenerator,
  type_validation? : StreamingToolCallTypeValidation = NoToolCallTypeValidation,
  extract_metadata? : StreamingToolCallMetadataExtractor,
  build_tool_call_provider_metadata? : StreamingToolCallMetadataBuilder,
) -> StreamingToolCallTracker {
  let resolved_extract_metadata = extract_metadata.unwrap_or(
    default_streaming_tool_call_metadata,
  )
  let resolved_metadata_builder = build_tool_call_provider_metadata.unwrap_or(
    identity_streaming_tool_call_metadata,
  )
  {
    calls: [],
    calls_by_id: {},
    calls_by_index: {},
    latest_call: None,
    generate_id: id_generator.unwrap_or(generate_id),
    type_validation,
    extract_metadata: resolved_extract_metadata,
    build_tool_call_provider_metadata: resolved_metadata_builder,
  }
}

///|
fn StreamingToolCallTracker::validate_type(
  self : StreamingToolCallTracker,
  delta : StreamingToolCallDelta,
) -> Unit raise {
  let invalid = match self.type_validation {
    NoToolCallTypeValidation => false
    ValidateToolCallTypeIfPresent =>
      match delta.tool_type {
        Some(value) => value != "function"
        None => false
      }
    RequireFunctionToolCallType => delta.tool_type != Some("function")
  }
  if invalid {
    raise @provider.InvalidResponseDataError(
      message="Expected 'function' type.",
      data=delta.data,
    )
  }
}

///|
fn StreamingToolCallTracker::process_new(
  self : StreamingToolCallTracker,
  delta : StreamingToolCallDelta,
  events : Array[StreamingToolCallLifecycleEvent],
) -> TrackedStreamingToolCall raise {
  self.validate_type(delta)
  let raw_id = match delta.id {
    Some(value) => value
    None =>
      raise @provider.InvalidResponseDataError(
        message="Expected 'id' to be a string.",
        data=delta.data,
      )
  }
  let name = match delta.function_name {
    Some(value) => value
    None =>
      raise @provider.InvalidResponseDataError(
        message="Expected 'function.name' to be a string.",
        data=delta.data,
      )
  }
  // An empty id is treated as absent: generate a stable one so tool calls
  // are never emitted with blank identifiers.
  let id = if raw_id == "" { (self.generate_id)() } else { raw_id }
  let arguments = delta.arguments_delta.unwrap_or("")
  let call : TrackedStreamingToolCall = {
    id,
    name,
    arguments: StringBuilder(),
    metadata: (self.extract_metadata)(delta),
    has_finished: false,
    final_call: None,
  }
  call.arguments.write_string(arguments)
  self.calls.push(call)
  if id != "" {
    self.calls_by_id[id] = call
  }
  events.push(StreamingToolInputStart(id~, tool_name=name))
  if arguments != "" {
    events.push(StreamingToolInputDelta(id~, delta=arguments))
  }
  call
}

///|
fn TrackedStreamingToolCall::append_delta(
  self : TrackedStreamingToolCall,
  delta : StreamingToolCallDelta,
  events : Array[StreamingToolCallLifecycleEvent],
) -> Unit {
  if self.has_finished {
    return
  }
  match delta.arguments_delta {
    Some(arguments) => {
      self.arguments.write_string(arguments)
      events.push(StreamingToolInputDelta(id=self.id, delta=arguments))
    }
    None => ()
  }
}

///|
fn StreamingToolCallTracker::process_delta_events(
  self : StreamingToolCallTracker,
  delta : StreamingToolCallDelta,
) -> Array[StreamingToolCallLifecycleEvent] raise {
  let events : Array[StreamingToolCallLifecycleEvent] = []
  let existing = match delta.id {
    Some(value) if value != "" => self.calls_by_id.get(value)
    _ =>
      match delta.index {
        Some(index) => self.calls_by_index.get(index)
        None => self.latest_call
      }
  }
  let call = match existing {
    Some(call) => {
      call.append_delta(delta, events)
      call
    }
    None => self.process_new(delta, events)
  }
  if delta.index is Some(index) {
    guard index >= 0 else {
      raise @provider.InvalidResponseDataError(
        message="Tool call index must be non-negative.",
        data=delta.data,
      )
    }
    self.calls_by_index[index] = call
  }
  self.latest_call = Some(call)
  events
}

///|
/// Process one delta and return events for the original stream contract.
pub fn StreamingToolCallTracker::process_delta(
  self : StreamingToolCallTracker,
  delta : StreamingToolCallDelta,
) -> Array[@provider.StreamEvent] raise {
  self.process_delta_events(delta).map(event => event.to_stream_event())
}

///|
/// Process one delta and return AI SDK V4 tool-input lifecycle parts.
pub fn StreamingToolCallTracker::process_delta_v4(
  self : StreamingToolCallTracker,
  delta : StreamingToolCallDelta,
) -> Array[@provider.LanguageModelV4StreamPart] raise {
  self.process_delta_events(delta).map(event => event.to_v4_stream_part())
}

///|
fn TrackedStreamingToolCall::to_raw_call(
  self : TrackedStreamingToolCall,
) -> @provider.ToolCall {
  @provider.ToolCall::new(
    id=self.id,
    name=self.name,
    arguments=self.arguments.to_string(),
    provider_metadata=self.metadata,
  )
}

///|
fn StreamingToolCallTracker::finish_call(
  self : StreamingToolCallTracker,
  call : TrackedStreamingToolCall,
) -> @provider.ToolCall {
  let finished = @provider.ToolCall::new(
    id=call.id,
    name=call.name,
    arguments=call.arguments.to_string(),
    provider_metadata=(self.build_tool_call_provider_metadata)(call.metadata),
  )
  call.final_call = Some(finished)
  finished
}

///|
fn StreamingToolCallTracker::flush_events(
  self : StreamingToolCallTracker,
) -> Array[StreamingToolCallLifecycleEvent] {
  let events : Array[StreamingToolCallLifecycleEvent] = []
  for call in self.calls {
    if !call.has_finished {
      let finished = self.finish_call(call)
      events.push(StreamingToolInputEnd(finished.id))
      events.push(StreamingToolCallReady(finished))
      call.has_finished = true
    }
  }
  events
}

///|
/// Finalize every unfinished call using the original stream vocabulary.
pub fn StreamingToolCallTracker::flush(
  self : StreamingToolCallTracker,
) -> Array[@provider.StreamEvent] {
  self.flush_events().map(event => event.to_stream_event())
}

///|
/// Finalize every unfinished call using AI SDK V4 stream parts.
pub fn StreamingToolCallTracker::flush_v4(
  self : StreamingToolCallTracker,
) -> Array[@provider.LanguageModelV4StreamPart] {
  self.flush_events().map(event => event.to_v4_stream_part())
}

///|
/// Return all tracked calls in provider-index order.
///
/// This read view lets MoonBit stream adapters build their final normalized
/// response without maintaining a second tool-call accumulator.
pub fn StreamingToolCallTracker::calls(
  self : StreamingToolCallTracker,
) -> Array[@provider.ToolCall] {
  let calls : Array[@provider.ToolCall] = []
  for call in self.calls {
    match call.final_call {
      Some(finished) => calls.push(finished)
      None => calls.push(call.to_raw_call())
    }
  }
  calls
}

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
/// Tracks interleaved streaming tool calls and owns their stream lifecycle.
///
/// A complete-looking JSON prefix is never finalized early. All unfinished
/// calls emit `ToolInputEnd` followed by `ToolCallReady` only from `flush`.
pub struct StreamingToolCallTracker {
  priv ids : Array[String?]
  priv names : Array[String]
  priv arguments : Array[StringBuilder]
  priv provider_metadata : Array[Map[String, Json]]
  priv final_calls : Array[@provider.ToolCall?]
  priv received : Array[Bool]
  priv finished : Array[Bool]
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
    ids: [],
    names: [],
    arguments: [],
    provider_metadata: [],
    final_calls: [],
    received: [],
    finished: [],
    generate_id: id_generator.unwrap_or(generate_id),
    type_validation,
    extract_metadata: resolved_extract_metadata,
    build_tool_call_provider_metadata: resolved_metadata_builder,
  }
}

///|
fn StreamingToolCallTracker::ensure(
  self : StreamingToolCallTracker,
  index : Int,
) -> Unit {
  while self.received.length() <= index {
    self.ids.push(None)
    self.names.push("")
    self.arguments.push(StringBuilder::new())
    self.provider_metadata.push(Map([]))
    self.final_calls.push(None)
    self.received.push(false)
    self.finished.push(false)
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
  index : Int,
  delta : StreamingToolCallDelta,
) -> Array[StreamingToolCallLifecycleEvent] raise {
  self.validate_type(delta)
  let id = match delta.id {
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
  let arguments = delta.arguments_delta.unwrap_or("")
  self.ids[index] = Some(id)
  self.names[index] = name
  self.arguments[index].write_string(arguments)
  self.provider_metadata[index] = (self.extract_metadata)(delta)
  self.received[index] = true
  let events : Array[StreamingToolCallLifecycleEvent] = [
    StreamingToolInputStart(id~, tool_name=name),
  ]
  if arguments != "" {
    events.push(StreamingToolInputDelta(id~, delta=arguments))
  }
  events
}

///|
fn StreamingToolCallTracker::process_existing(
  self : StreamingToolCallTracker,
  index : Int,
  delta : StreamingToolCallDelta,
) -> Array[StreamingToolCallLifecycleEvent] {
  if self.finished[index] {
    return []
  }
  match delta.arguments_delta {
    Some(arguments) => {
      self.arguments[index].write_string(arguments)
      [StreamingToolInputDelta(id=self.ids[index].unwrap(), delta=arguments)]
    }
    None => []
  }
}

///|
fn StreamingToolCallTracker::process_delta_events(
  self : StreamingToolCallTracker,
  delta : StreamingToolCallDelta,
) -> Array[StreamingToolCallLifecycleEvent] raise {
  let index = delta.index.unwrap_or(self.received.length())
  guard index >= 0 else {
    raise @provider.InvalidResponseDataError(
      message="Tool call index must be non-negative.",
      data=delta.data,
    )
  }
  self.ensure(index)
  if self.received[index] {
    self.process_existing(index, delta)
  } else {
    self.process_new(index, delta)
  }
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
fn StreamingToolCallTracker::resolved_id(
  self : StreamingToolCallTracker,
  index : Int,
) -> String {
  match self.ids[index] {
    Some(value) => value
    None => (self.generate_id)()
  }
}

///|
fn StreamingToolCallTracker::raw_call_at(
  self : StreamingToolCallTracker,
  index : Int,
) -> @provider.ToolCall {
  @provider.ToolCall::new(
    id=self.resolved_id(index),
    name=self.names[index],
    arguments=self.arguments[index].to_string(),
    provider_metadata=self.provider_metadata[index],
  )
}

///|
fn StreamingToolCallTracker::finish_call_at(
  self : StreamingToolCallTracker,
  index : Int,
) -> @provider.ToolCall {
  let call = @provider.ToolCall::new(
    id=self.resolved_id(index),
    name=self.names[index],
    arguments=self.arguments[index].to_string(),
    provider_metadata=(self.build_tool_call_provider_metadata)(
      self.provider_metadata[index],
    ),
  )
  self.final_calls[index] = Some(call)
  call
}

///|
fn StreamingToolCallTracker::flush_events(
  self : StreamingToolCallTracker,
) -> Array[StreamingToolCallLifecycleEvent] {
  let events : Array[StreamingToolCallLifecycleEvent] = []
  for index in 0..<self.received.length() {
    if self.received[index] && !self.finished[index] {
      let call = self.finish_call_at(index)
      events.push(StreamingToolInputEnd(call.id))
      events.push(StreamingToolCallReady(call))
      self.finished[index] = true
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
  for index in 0..<self.received.length() {
    if self.received[index] {
      match self.final_calls[index] {
        Some(call) => calls.push(call)
        None => calls.push(self.raw_call_at(index))
      }
    }
  }
  calls
}

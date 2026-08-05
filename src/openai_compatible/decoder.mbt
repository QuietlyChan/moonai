///|
/// Stateful decoder for OpenAI-compatible Chat Completions SSE.
pub struct OpenAICompatibleStreamDecoder {
  priv sse : @provider_utils.EventSourceBuffer
  priv include_raw_chunks : Bool
  priv generate_id : @provider_utils.IdGenerator
  priv generate_reasoning_ids : Bool
  priv text : StringBuilder
  priv reasoning : StringBuilder
  priv tools : @provider_utils.ToolCallDeltaAssembler
  priv tool_stream_ids : Array[String]
  priv pending_tool_ids : Array[String]
  priv pending_tool_arguments : Array[StringBuilder]
  priv pending_tool_metadata : Array[Map[String, Json]]
  priv pending_tool_received : Array[Bool]
  priv forwarded_tool_calls : Array[Bool]
  priv mut usage : @provider.Usage
  priv mut raw_usage : Json?
  priv mut finish_reason : @provider.FinishReason
  priv mut finish_reason_raw : String?
  priv provider_name : String
  priv metadata_key : String
  priv error_structure : OpenAICompatibleErrorStructure
  priv convert_usage : (Json) -> @provider.Usage
  priv stream_metadata_extractor : OpenAICompatibleStreamMetadataExtractor?
  priv mut response_metadata : @provider.ResponseMetadata?
  priv mut provider_metadata : Map[String, Json]
  priv mut text_started : Bool
  priv mut reasoning_started : Bool
  priv mut reasoning_stream_id : String
  priv mut metadata_emitted : Bool
  priv mut finalized : Bool
}

///|
/// Create an empty OpenAI-compatible stream decoder.
pub fn OpenAICompatibleStreamDecoder::new(
  include_raw_chunks? : Bool = false,
  provider_name? : String = "",
  metadata_key? : String = "",
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : (Json) -> @provider.Usage = convert_openai_compatible_chat_usage,
  id_generator? : @provider_utils.IdGenerator,
  generate_reasoning_ids? : Bool = false,
) -> OpenAICompatibleStreamDecoder {
  let resolved_metadata_key = if metadata_key != "" {
    metadata_key
  } else if provider_name != "" {
    @provider_utils.resolve_provider_options_key(
      compatible_provider_options_name(provider_name),
      Map([]),
    )
  } else {
    "openai-compatible"
  }
  let resolved_id_generator = id_generator.unwrap_or(
    @provider_utils.generate_id,
  )
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    generate_id: resolved_id_generator,
    generate_reasoning_ids,
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    tools: @provider_utils.ToolCallDeltaAssembler::new(
      id_generator=resolved_id_generator,
    ),
    tool_stream_ids: [],
    pending_tool_ids: [],
    pending_tool_arguments: [],
    pending_tool_metadata: [],
    pending_tool_received: [],
    forwarded_tool_calls: [],
    usage: @provider.Usage::zero(),
    raw_usage: None,
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    provider_name,
    metadata_key: resolved_metadata_key,
    error_structure,
    convert_usage,
    stream_metadata_extractor: metadata_extractor.map(extractor => {
      extractor.create_stream_extractor()
    }),
    response_metadata: None,
    provider_metadata: Map([(resolved_metadata_key, Json::empty_object())]),
    text_started: false,
    reasoning_started: false,
    reasoning_stream_id: "",
    metadata_emitted: false,
    finalized: false,
  }
}

///|
fn OpenAICompatibleStreamDecoder::start_reasoning(
  self : OpenAICompatibleStreamDecoder,
  events : Array[@provider.StreamEvent],
) -> String {
  if !self.reasoning_started {
    self.reasoning_started = true
    let generated = if self.generate_reasoning_ids {
      (self.generate_id)()
    } else {
      ""
    }
    self.reasoning_stream_id = if generated == "" {
      "reasoning-0"
    } else {
      generated
    }
    events.push(@provider.ReasoningStart(self.reasoning_stream_id))
  }
  self.reasoning_stream_id
}

///|
fn OpenAICompatibleStreamDecoder::close_reasoning(
  self : OpenAICompatibleStreamDecoder,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if self.reasoning_started {
    self.reasoning_started = false
    events.push(@provider.ReasoningEnd(self.reasoning_stream_id))
    self.reasoning_stream_id = ""
  }
}

///|
/// Retain identity and provider-specific fields carried by stream chunks.
fn OpenAICompatibleStreamDecoder::record_json(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let chunk_metadata = @provider.ResponseMetadata::from_json(json)
  if !chunk_metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, chunk_metadata),
    )
  }
  if !self.metadata_emitted {
    self.metadata_emitted = true
    events.push(@provider.ResponseMetadataReady(chunk_metadata))
  }
  if self.provider_name != "" {
    self.provider_metadata = @provider.merge_provider_metadata(
      self.provider_metadata,
      @provider_utils.provider_metadata_from_json(json, self.provider_name),
    )
  }
  self.provider_metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    openai_compatible_prediction_metadata(json, self.metadata_key),
  )
  if self.stream_metadata_extractor is Some(extractor) {
    extractor.process_chunk(json)
  }
}

///|
fn finish_reason_is_known(reason : @provider.FinishReason) -> Bool {
  !(reason is @provider.Unknown(""))
}

///|
fn OpenAICompatibleStreamDecoder::ensure_tool_stream_id(
  self : OpenAICompatibleStreamDecoder,
  index : Int,
  stream_id : String,
) -> Unit {
  while self.tool_stream_ids.length() <= index {
    self.tool_stream_ids.push("")
  }
  if self.tool_stream_ids[index] == "" {
    self.tool_stream_ids[index] = stream_id
  }
}

///|
fn OpenAICompatibleStreamDecoder::ensure_pending_tool(
  self : OpenAICompatibleStreamDecoder,
  index : Int,
  data : Json,
) -> Unit raise {
  guard index >= 0 else {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible tool call index must be non-negative",
      data~,
    )
  }
  while self.pending_tool_ids.length() <= index {
    self.pending_tool_ids.push("")
    self.pending_tool_arguments.push(StringBuilder::new())
    self.pending_tool_metadata.push(Map([]))
    self.pending_tool_received.push(false)
    self.forwarded_tool_calls.push(false)
  }
}

///|
fn OpenAICompatibleStreamDecoder::apply_forwarded_tool_delta(
  self : OpenAICompatibleStreamDecoder,
  index : Int,
  id : String?,
  name : String?,
  arguments_delta : String?,
  provider_metadata : Map[String, Json],
  events : Array[@provider.StreamEvent],
) -> Unit raise {
  let applied = self.tools.apply(
    @provider_utils.ToolCallDelta::new(
      index~,
      id?,
      name?,
      arguments_delta?,
      provider_metadata~,
    ),
  )
  self.ensure_tool_stream_id(index, applied.stream_id)
  if applied.started {
    events.push(
      @provider.ToolInputStart(
        id=applied.stream_id,
        tool_name=applied.tool_name,
      ),
    )
  }
  if applied.arguments_delta != "" {
    events.push(
      @provider.ToolInputDelta(
        id=applied.stream_id,
        delta=applied.arguments_delta,
      ),
    )
  }
}

///|
fn OpenAICompatibleStreamDecoder::apply_tool_delta(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
  fallback_index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit raise {
  guard json is Object(_) else { return }
  let index = match json {
    { "index": Number(value, ..), .. } => value.to_int()
    _ => fallback_index
  }
  let id = match json {
    { "id": String(value), .. } => Some(value)
    _ => None
  }
  let name = match json {
    { "function": { "name": String(value), .. }, .. } => Some(value)
    _ => None
  }
  let arguments_delta = match json {
    { "function": { "arguments": String(value), .. }, .. } => Some(value)
    _ => None
  }
  let provider_metadata = openai_compatible_thought_signature_metadata(
    json,
    self.metadata_key,
  )
  self.ensure_pending_tool(index, json)
  if self.forwarded_tool_calls[index] {
    self.apply_forwarded_tool_delta(
      index, id, name, arguments_delta, provider_metadata, events,
    )
    return
  }
  self.pending_tool_received[index] = true
  if id is Some(value) && value != "" && self.pending_tool_ids[index] == "" {
    self.pending_tool_ids[index] = value
  }
  if arguments_delta is Some(value) && value != "" {
    self.pending_tool_arguments[index].write_string(value)
  }
  self.pending_tool_metadata[index] = @provider.merge_provider_metadata(
    self.pending_tool_metadata[index],
    provider_metadata,
  )
  if name is Some(value) && value != "" {
    let buffered_id = if self.pending_tool_ids[index] == "" {
      None
    } else {
      Some(self.pending_tool_ids[index])
    }
    self.apply_forwarded_tool_delta(
      index,
      buffered_id,
      Some(value),
      Some(self.pending_tool_arguments[index].to_string()),
      self.pending_tool_metadata[index],
      events,
    )
    self.forwarded_tool_calls[index] = true
  }
}

///|
fn OpenAICompatibleStreamDecoder::apply_json(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
) -> Array[@provider.StreamEvent] raise {
  let events : Array[@provider.StreamEvent] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": usage, .. } => {
      self.usage = (self.convert_usage)(usage)
      self.raw_usage = Some(usage)
    }
    _ => ()
  }
  match json {
    { "choices": [{ "delta": Object(delta), .. }, ..], .. } => {
      let reasoning = match delta {
        { "reasoning_content": String(value), .. } => value
        { "reasoning": String(value), .. } => value
        { "reasoning_delta": String(value), .. } => value
        _ => ""
      }
      if reasoning != "" {
        let reasoning_id = self.start_reasoning(events)
        self.reasoning.write_string(reasoning)
        events.push(@provider.ReasoningDelta(id=reasoning_id, delta=reasoning))
      }
      if delta is { "content": String(content), .. } && content != "" {
        self.close_reasoning(events)
        if !self.text_started {
          self.text_started = true
          events.push(@provider.TextStart("text-0"))
        }
        self.text.write_string(content)
        events.push(@provider.TextDelta(id="text-0", delta=content))
      }
      if delta is { "tool_calls": Array(calls), .. } {
        self.close_reasoning(events)
        for index, call in calls {
          self.apply_tool_delta(call, index, events)
        }
      }
    }
    _ => ()
  }
  match json {
    { "choices": [{ "finish_reason": String(reason), .. }, ..], .. } => {
      self.finish_reason = @provider.FinishReason::from_openai(reason)
      self.finish_reason_raw = Some(reason)
    }
    _ => ()
  }
  events
}

///|
fn OpenAICompatibleStreamDecoder::first_unresolved_tool_call(
  self : OpenAICompatibleStreamDecoder,
) -> Int? {
  for index in 0..<self.pending_tool_received.length() {
    if self.pending_tool_received[index] && !self.forwarded_tool_calls[index] {
      return Some(index)
    }
  }
  None
}

///|
fn OpenAICompatibleStreamDecoder::final_events(
  self : OpenAICompatibleStreamDecoder,
) -> Array[@provider.StreamEvent] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.StreamEvent] = []
  if self.first_unresolved_tool_call() is Some(index) {
    self.finish_reason = @provider.Error
    self.finish_reason_raw = Some("invalid_tool_call")
    events.push(
      @provider.StreamError(
        "OpenAI-compatible tool call at index \{index} is missing function.name",
      ),
    )
  }
  if self.text_started {
    events.push(@provider.TextEnd("text-0"))
  }
  self.close_reasoning(events)
  if self.finish_reason is @provider.Error {
    for stream_id in self.tool_stream_ids {
      if stream_id != "" {
        events.push(@provider.ToolInputEnd(stream_id))
      }
    }
  } else {
    let calls = self.tools.calls()
    for index, call in calls {
      let stream_id = if index < self.tool_stream_ids.length() &&
        self.tool_stream_ids[index] != "" {
        self.tool_stream_ids[index]
      } else {
        call.id
      }
      events.push(@provider.ToolInputEnd(stream_id))
      events.push(@provider.ToolCallReady(call))
    }
  }
  events.push(@provider.Finish(usage=self.usage, reason=self.finish_reason))
  events
}

///|
fn OpenAICompatibleStreamDecoder::decode_data(
  self : OpenAICompatibleStreamDecoder,
  data : String,
) -> @provider_utils.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => {
      self.finish_reason = @provider.Error
      self.finish_reason_raw = Some("invalid_json")
      return {
        events: [
          @provider.StreamError(
            "OpenAI-compatible stream decode error: \{error}; data: \{data}",
          ),
        ],
        consumed_event: true,
        done: false,
      }
    }
  }
  if self.error_structure.message(json) is Some(message) {
    self.finish_reason = @provider.Error
    self.finish_reason_raw = Some("error")
    let events : Array[@provider.StreamEvent] = [@provider.StreamError(message)]
    let terminal_events = self.final_events()
    for event in terminal_events {
      events.push(event)
    }
    if self.include_raw_chunks {
      let all_events : Array[@provider.StreamEvent] = [@provider.Raw(json)]
      for event in events {
        all_events.push(event)
      }
      return { events: all_events, consumed_event: true, done: true }
    }
    return { events, consumed_event: true, done: true }
  }
  let events : Array[@provider.StreamEvent] = []
  self.record_json(json, events)
  let decoded_events = self.apply_json(json)
  for event in decoded_events {
    events.push(event)
  }
  if self.include_raw_chunks {
    let all_events : Array[@provider.StreamEvent] = [@provider.Raw(json)]
    for event in events {
      all_events.push(event)
    }
    { events: all_events, consumed_event: true, done: false }
  } else {
    { events, consumed_event: true, done: false }
  }
}

///|
/// Feed one physical SSE line.
pub fn OpenAICompatibleStreamDecoder::feed_line(
  self : OpenAICompatibleStreamDecoder,
  raw : String,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
pub fn OpenAICompatibleStreamDecoder::flush_buffered(
  self : OpenAICompatibleStreamDecoder,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.flush() {
    Some(data) => {
      let batch = self.decode_data(data)
      if batch.done || !finish_reason_is_known(self.finish_reason) {
        batch
      } else {
        let events = batch.events
        let terminal_events = self.final_events()
        for event in terminal_events {
          events.push(event)
        }
        { events, consumed_event: batch.consumed_event, done: true }
      }
    }
    None =>
      if self.finalized {
        @provider_utils.DecodeBatch::empty(true)
      } else if finish_reason_is_known(self.finish_reason) {
        { events: self.final_events(), consumed_event: false, done: true }
      } else {
        @provider_utils.DecodeBatch::empty(false)
      }
  }
}

///|
/// Return the accumulated normalized response.
pub fn OpenAICompatibleStreamDecoder::response(
  self : OpenAICompatibleStreamDecoder,
) -> @provider.ChatResponse {
  let provider_metadata = match self.stream_metadata_extractor {
    Some(extractor) =>
      @provider.merge_provider_metadata(
        extractor.build_metadata(),
        self.provider_metadata,
      )
    None => self.provider_metadata
  }
  @provider.ChatResponse::new(
    self.text.to_string(),
    self.reasoning.to_string(),
    if self.finish_reason is @provider.Error {
      []
    } else {
      self.tools.calls()
    },
    self.usage,
    self.finish_reason,
  ).with_diagnostics(None, self.response_metadata, provider_metadata, [])
}

///|
/// Return V4 usage with the latest provider-native usage object.
pub fn OpenAICompatibleStreamDecoder::v4_usage(
  self : OpenAICompatibleStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  match self.raw_usage {
    Some(_) =>
      @provider.LanguageModelV4Usage::from_usage(self.usage).with_raw(
        self.raw_usage,
      )
    None => @provider.LanguageModelV4Usage::unknown()
  }
}

///|
/// Return V4 finish reason with the provider-native finish string.
pub fn OpenAICompatibleStreamDecoder::v4_finish_reason(
  self : OpenAICompatibleStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  @provider.LanguageModelV4FinishReason::from_finish_reason(self.finish_reason).with_raw(
    self.finish_reason_raw,
  )
}

///|
/// Return metadata accumulated from compatible stream chunks.
pub fn OpenAICompatibleStreamDecoder::provider_metadata_snapshot(
  self : OpenAICompatibleStreamDecoder,
) -> Map[String, Json] {
  match self.stream_metadata_extractor {
    Some(extractor) =>
      @provider.merge_provider_metadata(
        extractor.build_metadata(),
        self.provider_metadata,
      )
    None => self.provider_metadata
  }
}

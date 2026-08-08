///|
/// Stateful decoder for OpenAI-compatible Chat Completions SSE.
priv struct OpenAICompatibleStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  generate_id : @provider_utils.IdGenerator
  generate_reasoning_ids : Bool
  text_stream_id : String
  close_text_before_reasoning : Bool
  close_text_before_tool_calls : Bool
  validate_stream_chunk : OpenAICompatibleJsonValidator
  text : StringBuilder
  reasoning : StringBuilder
  tools : @provider_utils.StreamingToolCallTracker
  pending_tool_ids : Array[String?]
  pending_tool_arguments : Array[StringBuilder]
  pending_tool_metadata : Array[Map[String, Json]]
  pending_tool_data : Array[Json]
  pending_tool_received : Array[Bool]
  forwarded_tool_calls : Array[Bool]
  mut raw_usage : Json?
  mut finish_reason : @provider.FinishReason
  mut finish_reason_raw : String?
  provider_name : String
  metadata_key : String
  error_structure : OpenAICompatibleErrorStructure
  convert_usage : OpenAICompatibleUsageConverter
  stream_metadata_extractor : OpenAICompatibleStreamMetadataExtractor?
  mut response_metadata : @provider.ResponseMetadata?
  mut provider_metadata : Map[String, Json]
  mut text_started : Bool
  mut reasoning_started : Bool
  mut reasoning_stream_id : String
  mut metadata_emitted : Bool
  mut finalized : Bool
}

///|
/// Create an empty OpenAI-compatible stream decoder.
fn OpenAICompatibleStreamDecoder::new(
  include_raw_chunks : Bool,
  provider_name : String,
  metadata_key : String,
  error_structure : OpenAICompatibleErrorStructure,
  metadata_extractor : OpenAICompatibleMetadataExtractor?,
  convert_usage : OpenAICompatibleUsageConverter,
  id_generator : @provider_utils.IdGenerator,
  generate_reasoning_ids : Bool,
  text_stream_id : String,
  close_text_before_reasoning : Bool,
  close_text_before_tool_calls : Bool,
  validate_stream_chunk : OpenAICompatibleJsonValidator,
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
  let resolved_id_generator = id_generator
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    generate_id: resolved_id_generator,
    generate_reasoning_ids,
    text_stream_id,
    close_text_before_reasoning,
    close_text_before_tool_calls,
    validate_stream_chunk,
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    tools: @provider_utils.StreamingToolCallTracker::new(
      id_generator=resolved_id_generator,
    ),
    pending_tool_ids: [],
    pending_tool_arguments: [],
    pending_tool_metadata: [],
    pending_tool_data: [],
    pending_tool_received: [],
    forwarded_tool_calls: [],
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
fn OpenAICompatibleStreamDecoder::invalid_stream_chunk(
  self : OpenAICompatibleStreamDecoder,
  message : String,
  data : Json,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  self.finish_reason = @provider.Error
  self.finish_reason_raw = None
  let events : Array[@provider.LanguageModelV4StreamPart] = [
    @provider.V4Error(@provider.StreamErrorInfo::new(message, data~)),
  ]
  if self.include_raw_chunks {
    events.insert(0, @provider.V4Raw(data))
  }
  { events, consumed_event: true, done: false }
}

///|
fn OpenAICompatibleStreamDecoder::start_reasoning(
  self : OpenAICompatibleStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
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
    events.push(
      @provider.V4ReasoningStart(
        id=self.reasoning_stream_id,
        provider_metadata=Map([]),
      ),
    )
  }
  self.reasoning_stream_id
}

///|
fn OpenAICompatibleStreamDecoder::close_reasoning(
  self : OpenAICompatibleStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.reasoning_started {
    self.reasoning_started = false
    events.push(
      @provider.V4ReasoningEnd(
        id=self.reasoning_stream_id,
        provider_metadata=Map([]),
      ),
    )
    self.reasoning_stream_id = ""
  }
}

///|
fn OpenAICompatibleStreamDecoder::close_text(
  self : OpenAICompatibleStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.text_started {
    self.text_started = false
    events.push(
      @provider.V4TextEnd(id=self.text_stream_id, provider_metadata=Map([])),
    )
  }
}

///|
/// Retain identity and provider-specific fields carried by stream chunks.
fn OpenAICompatibleStreamDecoder::record_json(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  let chunk_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created"),
  )
  if !chunk_metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, chunk_metadata),
    )
  }
  if !self.metadata_emitted {
    self.metadata_emitted = true
    events.push(@provider.V4ResponseMetadataReady(chunk_metadata))
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
    self.pending_tool_ids.push(None)
    self.pending_tool_arguments.push(StringBuilder::new())
    self.pending_tool_metadata.push(Map([]))
    self.pending_tool_data.push(data)
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
  data : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit raise {
  for
    event in self.tools.process_delta_v4(
      @provider_utils.StreamingToolCallDelta::new(
        index~,
        id?,
        function_name?=name,
        arguments_delta?,
        provider_metadata~,
        data~,
      ),
    ) {
    events.push(event)
  }
}

///|
fn OpenAICompatibleStreamDecoder::apply_tool_delta(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
  fallback_index : Int,
  events : Array[@provider.LanguageModelV4StreamPart],
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
      index, id, name, arguments_delta, provider_metadata, json, events,
    )
    return
  }
  self.pending_tool_received[index] = true
  if id is Some(_) && self.pending_tool_ids[index] is None {
    self.pending_tool_ids[index] = id
  }
  if arguments_delta is Some(value) && value != "" {
    self.pending_tool_arguments[index].write_string(value)
  }
  self.pending_tool_metadata[index] = @provider.merge_provider_metadata(
    self.pending_tool_metadata[index],
    provider_metadata,
  )
  if name is Some(value) {
    self.apply_forwarded_tool_delta(
      index,
      self.pending_tool_ids[index],
      Some(value),
      Some(self.pending_tool_arguments[index].to_string()),
      self.pending_tool_metadata[index],
      json,
      events,
    )
    self.forwarded_tool_calls[index] = true
  }
}

///|
fn OpenAICompatibleStreamDecoder::apply_json(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
) -> Array[@provider.LanguageModelV4StreamPart] raise {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": usage, .. } => self.raw_usage = Some(usage)
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
        if self.close_text_before_reasoning {
          self.close_text(events)
        }
        let reasoning_id = self.start_reasoning(events)
        self.reasoning.write_string(reasoning)
        events.push(
          @provider.V4ReasoningDelta(
            id=reasoning_id,
            delta=reasoning,
            provider_metadata=Map([]),
          ),
        )
      }
      if delta is { "content": String(content), .. } && content != "" {
        self.close_reasoning(events)
        if !self.text_started {
          self.text_started = true
          events.push(
            @provider.V4TextStart(
              id=self.text_stream_id,
              provider_metadata=Map([]),
            ),
          )
        }
        self.text.write_string(content)
        events.push(
          @provider.V4TextDelta(
            id=self.text_stream_id,
            delta=content,
            provider_metadata=Map([]),
          ),
        )
      }
      if delta is { "tool_calls": Array(calls), .. } {
        self.close_reasoning(events)
        if self.close_text_before_tool_calls {
          self.close_text(events)
        }
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
) -> Array[@provider.LanguageModelV4StreamPart] raise {
  if self.finalized {
    return []
  }
  if self.first_unresolved_tool_call() is Some(index) {
    let _ = self.tools.process_delta(
      @provider_utils.StreamingToolCallDelta::new(
        index~,
        id?=self.pending_tool_ids[index],
        arguments_delta=self.pending_tool_arguments[index].to_string(),
        provider_metadata=self.pending_tool_metadata[index],
        data=self.pending_tool_data[index],
      ),
    )
  }
  self.finalized = true
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.close_text(events)
  self.close_reasoning(events)
  for event in self.tools.flush_v4() {
    events.push(event)
  }
  events.push(
    @provider.V4Finish(
      usage=self.v4_usage(),
      reason=self.v4_finish_reason(),
      provider_metadata=self.provider_metadata_snapshot(),
    ),
  )
  events
}

///|
fn OpenAICompatibleStreamDecoder::decode_data(
  self : OpenAICompatibleStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error =>
      return self.invalid_stream_chunk(
        "OpenAI-compatible stream decode error: \{error}; data: \{data}",
        Json::string(data),
      )
  }
  if self.error_structure.message(json) is Some(message) {
    if self.stream_metadata_extractor is Some(extractor) {
      extractor.process_chunk(json)
    }
    self.finish_reason = @provider.Error
    self.finish_reason_raw = None
    let error_data = match json {
      { "error": value, .. } => value
      _ => json
    }
    let events : Array[@provider.LanguageModelV4StreamPart] = [
      @provider.V4Error(
        @provider.StreamErrorInfo::new(message, data=error_data),
      ),
    ]
    if self.include_raw_chunks {
      events.insert(0, @provider.V4Raw(json))
    }
    return { events, consumed_event: true, done: false }
  }
  if (self.validate_stream_chunk)(json) is Some(message) {
    return self.invalid_stream_chunk(message, json)
  }
  if self.stream_metadata_extractor is Some(extractor) {
    extractor.process_chunk(json)
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.record_json(json, events)
  let decoded_events = self.apply_json(json)
  for event in decoded_events {
    events.push(event)
  }
  if self.include_raw_chunks {
    let all_events : Array[@provider.LanguageModelV4StreamPart] = [
      @provider.V4Raw(json),
    ]
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
fn OpenAICompatibleStreamDecoder::feed_line(
  self : OpenAICompatibleStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
fn OpenAICompatibleStreamDecoder::flush_buffered(
  self : OpenAICompatibleStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Finish the protocol transform after the transport reports a normal EOF.
fn OpenAICompatibleStreamDecoder::finish_stream(
  self : OpenAICompatibleStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  if self.finalized {
    @provider_utils.SseDecodeBatch::empty(true)
  } else {
    { events: self.final_events(), consumed_event: false, done: true }
  }
}

///|
/// Return V4 usage with the latest provider-native usage object.
fn OpenAICompatibleStreamDecoder::v4_usage(
  self : OpenAICompatibleStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  (self.convert_usage)(self.raw_usage)
}

///|
/// Return V4 finish reason with the provider-native finish string.
fn OpenAICompatibleStreamDecoder::v4_finish_reason(
  self : OpenAICompatibleStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  @provider.LanguageModelV4FinishReason::from_finish_reason(self.finish_reason).with_raw(
    self.finish_reason_raw,
  )
}

///|
/// Return metadata accumulated from compatible stream chunks.
fn OpenAICompatibleStreamDecoder::provider_metadata_snapshot(
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

///|
/// Return response identity accumulated from compatible stream chunks.
fn OpenAICompatibleStreamDecoder::response_metadata_snapshot(
  self : OpenAICompatibleStreamDecoder,
) -> @provider.ResponseMetadata? {
  self.response_metadata
}

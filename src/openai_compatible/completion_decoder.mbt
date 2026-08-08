///|
/// Stateful decoder for OpenAI-compatible completion SSE.
priv struct OpenAICompatibleCompletionStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  text : StringBuilder
  mut raw_usage : Json?
  mut finish_reason : @provider.FinishReason
  mut finish_reason_raw : String?
  provider_name : String
  error_structure : OpenAICompatibleErrorStructure
  mut response_metadata : @provider.ResponseMetadata?
  mut provider_metadata : Map[String, Json]
  mut text_started : Bool
  mut metadata_emitted : Bool
  mut finalized : Bool
}

///|
/// Create an empty completion stream decoder.
fn OpenAICompatibleCompletionStreamDecoder::new(
  include_raw_chunks : Bool,
  provider_name : String,
  error_structure : OpenAICompatibleErrorStructure,
) -> OpenAICompatibleCompletionStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    text: StringBuilder::new(),
    raw_usage: None,
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    provider_name,
    error_structure,
    response_metadata: None,
    provider_metadata: Map([]),
    text_started: false,
    metadata_emitted: false,
    finalized: false,
  }
}

///|
fn OpenAICompatibleCompletionStreamDecoder::invalid_stream_chunk(
  self : OpenAICompatibleCompletionStreamDecoder,
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
/// Retain identity and provider-specific fields carried by stream chunks.
fn OpenAICompatibleCompletionStreamDecoder::record_json(
  self : OpenAICompatibleCompletionStreamDecoder,
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
}

///|
fn OpenAICompatibleCompletionStreamDecoder::apply_json(
  self : OpenAICompatibleCompletionStreamDecoder,
  json : Json,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": value, .. } => self.raw_usage = Some(value)
    _ => ()
  }
  match json {
    { "choices": [{ "text": String(value), .. }, ..], .. } => {
      self.text.write_string(value)
      events.push(
        @provider.V4TextDelta(id="0", delta=value, provider_metadata=Map([])),
      )
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
fn OpenAICompatibleCompletionStreamDecoder::final_events(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.text_started {
    events.push(@provider.V4TextEnd(id="0", provider_metadata=Map([])))
  }
  events.push(
    @provider.V4Finish(
      usage=self.v4_usage(),
      reason=self.v4_finish_reason(),
      provider_metadata=@provider.copy_provider_metadata(self.provider_metadata),
    ),
  )
  events
}

///|
fn OpenAICompatibleCompletionStreamDecoder::decode_data(
  self : OpenAICompatibleCompletionStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => {
      self.finish_reason = @provider.Error
      self.finish_reason_raw = None
      let events : Array[@provider.LanguageModelV4StreamPart] = [
        @provider.V4Error(
          @provider.StreamErrorInfo::new(
            "OpenAI-compatible completion stream decode error: \{error}; data: \{data}",
            data=Json::string(data),
          ),
        ),
      ]
      if self.include_raw_chunks {
        events.insert(0, @provider.V4Raw(Json::string(data)))
      }
      return { events, consumed_event: true, done: false }
    }
  }
  if self.error_structure.message(json) is Some(message) {
    let error_data = match json {
      { "error": value, .. } => value
      _ => json
    }
    let events : Array[@provider.LanguageModelV4StreamPart] = [
      @provider.V4Error(
        @provider.StreamErrorInfo::new(message, data=error_data),
      ),
    ]
    self.finish_reason = @provider.Error
    self.finish_reason_raw = None
    if self.include_raw_chunks {
      events.insert(0, @provider.V4Raw(json))
    }
    return { events, consumed_event: true, done: false }
  }
  if validate_openai_compatible_completion_chunk(json) is Some(message) {
    return self.invalid_stream_chunk(message, json)
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.record_json(json, events)
  if !self.text_started {
    self.text_started = true
    events.push(@provider.V4TextStart(id="0", provider_metadata=Map([])))
  }
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
fn OpenAICompatibleCompletionStreamDecoder::feed_line(
  self : OpenAICompatibleCompletionStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
fn OpenAICompatibleCompletionStreamDecoder::flush_buffered(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Finish the protocol transform after the transport reports a normal EOF.
fn OpenAICompatibleCompletionStreamDecoder::finish_stream(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    @provider_utils.SseDecodeBatch::empty(true)
  } else {
    { events: self.final_events(), consumed_event: false, done: true }
  }
}

///|
fn OpenAICompatibleCompletionStreamDecoder::v4_usage(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  convert_openai_compatible_completion_usage(self.raw_usage)
}

///|
fn OpenAICompatibleCompletionStreamDecoder::v4_finish_reason(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  @provider.LanguageModelV4FinishReason::from_finish_reason(self.finish_reason).with_raw(
    self.finish_reason_raw,
  )
}

///|
fn OpenAICompatibleCompletionStreamDecoder::response_metadata_snapshot(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @provider.ResponseMetadata? {
  self.response_metadata
}

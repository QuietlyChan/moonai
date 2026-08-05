///|
/// Stateful decoder for legacy OpenAI completion SSE.
pub struct OpenAICompatibleCompletionStreamDecoder {
  priv sse : @provider_utils.EventSourceBuffer
  priv include_raw_chunks : Bool
  priv text : StringBuilder
  priv mut usage : @provider.Usage
  priv mut finish_reason : @provider.FinishReason
  priv provider_name : String
  priv error_structure : OpenAICompatibleErrorStructure
  priv mut response_metadata : @provider.ResponseMetadata?
  priv mut provider_metadata : Map[String, Json]
  priv mut text_started : Bool
  priv mut metadata_emitted : Bool
  priv mut finalized : Bool
}

///|
/// Create an empty completion stream decoder.
pub fn OpenAICompatibleCompletionStreamDecoder::new(
  include_raw_chunks? : Bool = false,
  provider_name? : String = "",
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
) -> OpenAICompatibleCompletionStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    text: StringBuilder::new(),
    usage: @provider.Usage::zero(),
    finish_reason: @provider.Unknown(""),
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
/// Retain identity and provider-specific fields carried by stream chunks.
fn OpenAICompatibleCompletionStreamDecoder::record_json(
  self : OpenAICompatibleCompletionStreamDecoder,
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
}

///|
fn OpenAICompatibleCompletionStreamDecoder::apply_json(
  self : OpenAICompatibleCompletionStreamDecoder,
  json : Json,
) -> Array[@provider.StreamEvent] {
  let events : Array[@provider.StreamEvent] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": value, .. } =>
      self.usage = convert_openai_compatible_chat_usage(value)
    _ => ()
  }
  match json {
    { "choices": [{ "text": String(value), .. }, ..], .. } if value != "" => {
      if !self.text_started {
        self.text_started = true
        events.push(@provider.TextStart("text-0"))
      }
      self.text.write_string(value)
      events.push(@provider.TextDelta(id="text-0", delta=value))
    }
    _ => ()
  }
  match json {
    { "choices": [{ "finish_reason": String(reason), .. }, ..], .. } =>
      self.finish_reason = @provider.FinishReason::from_openai(reason)
    _ => ()
  }
  events
}

///|
fn OpenAICompatibleCompletionStreamDecoder::final_events(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> Array[@provider.StreamEvent] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.StreamEvent] = []
  if self.text_started {
    events.push(@provider.TextEnd("text-0"))
  }
  let reason = match self.finish_reason {
    @provider.Unknown(_) => @provider.Stop
    other => other
  }
  self.finish_reason = reason
  events.push(@provider.Finish(usage=self.usage, reason~))
  events
}

///|
fn OpenAICompatibleCompletionStreamDecoder::decode_data(
  self : OpenAICompatibleCompletionStreamDecoder,
  data : String,
) -> @provider_utils.DecodeBatch {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => {
      self.finish_reason = @provider.Error
      return {
        events: [
          @provider.StreamError(
            "OpenAI-compatible completion stream decode error: \{error}; data: \{data}",
          ),
        ],
        consumed_event: true,
        done: false,
      }
    }
  }
  if self.error_structure.message(json) is Some(message) {
    let events : Array[@provider.StreamEvent] = [@provider.StreamError(message)]
    self.finish_reason = @provider.Error
    for event in self.final_events() {
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
pub fn OpenAICompatibleCompletionStreamDecoder::feed_line(
  self : OpenAICompatibleCompletionStreamDecoder,
  raw : String,
) -> @provider_utils.DecodeBatch {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
pub fn OpenAICompatibleCompletionStreamDecoder::flush_buffered(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @provider_utils.DecodeBatch {
  match self.sse.flush() {
    Some(data) => {
      let batch = self.decode_data(data)
      if batch.done || !finish_reason_is_known(self.finish_reason) {
        batch
      } else {
        let events = batch.events
        for event in self.final_events() {
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
/// Return the accumulated completion response.
pub fn OpenAICompatibleCompletionStreamDecoder::response(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @provider.CompletionResponse {
  @provider.CompletionResponse::new(
    self.text.to_string(),
    self.usage,
    self.finish_reason,
  ).with_diagnostics(None, self.response_metadata, self.provider_metadata, [])
}

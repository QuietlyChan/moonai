///|
/// Convert OpenAI completion token accounting to provider-neutral usage.
fn openai_completion_usage(json : Json) -> @provider.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
  let output_tokens = @provider_utils.json_int_field(json, "completion_tokens")
  let total_tokens = @provider_utils.json_int_field(
    json,
    "total_tokens",
    default=input_tokens + output_tokens,
  )
  {
    input_tokens,
    output_tokens,
    total_tokens,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
}

///|
fn openai_completion_finish_known(reason : @provider.FinishReason) -> Bool {
  match reason {
    @provider.Unknown(value) => value != ""
    _ => true
  }
}

///|
/// Stateful SSE decoder owned by the official OpenAI completion model.
priv struct OpenAICompletionStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  text : StringBuilder
  mut usage : @provider.Usage
  mut finish_reason : @provider.FinishReason
  mut response_metadata : @provider.ResponseMetadata?
  logprobs : Array[Json]
  mut text_started : Bool
  mut metadata_emitted : Bool
  mut finalized : Bool
}

///|
fn OpenAICompletionStreamDecoder::new(
  include_raw_chunks~ : Bool,
) -> OpenAICompletionStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    text: StringBuilder::new(),
    usage: @provider.Usage::zero(),
    finish_reason: @provider.Unknown(""),
    response_metadata: None,
    logprobs: [],
    text_started: false,
    metadata_emitted: false,
    finalized: false,
  }
}

///|
fn OpenAICompletionStreamDecoder::record_json(
  self : OpenAICompletionStreamDecoder,
  json : Json,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let metadata = @provider.ResponseMetadata::from_json(json)
  if !metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, metadata),
    )
  }
  if !self.metadata_emitted {
    self.metadata_emitted = true
    events.push(@provider.ResponseMetadataReady(metadata))
  }
  match json {
    { "choices": [{ "logprobs": value, .. }, ..], .. } if !(value is Null) =>
      self.logprobs.push(value)
    _ => ()
  }
}

///|
fn OpenAICompletionStreamDecoder::apply_json(
  self : OpenAICompletionStreamDecoder,
  json : Json,
) -> Array[@provider.StreamEvent] {
  let events : Array[@provider.StreamEvent] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": value, .. } => self.usage = openai_completion_usage(value)
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
fn OpenAICompletionStreamDecoder::final_events(
  self : OpenAICompletionStreamDecoder,
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
fn OpenAICompletionStreamDecoder::decode_data(
  self : OpenAICompletionStreamDecoder,
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
            "OpenAI completion stream decode error: \{error}; data: \{data}",
          ),
        ],
        consumed_event: true,
        done: false,
      }
    }
  }
  if openai_error_message(json) is Some(message) {
    self.finish_reason = @provider.Error
    let events : Array[@provider.StreamEvent] = [@provider.StreamError(message)]
    for event in self.final_events() {
      events.push(event)
    }
    if self.include_raw_chunks {
      let raw_events : Array[@provider.StreamEvent] = [@provider.Raw(json)]
      for event in events {
        raw_events.push(event)
      }
      return { events: raw_events, consumed_event: true, done: true }
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
    let raw_events : Array[@provider.StreamEvent] = [@provider.Raw(json)]
    for event in events {
      raw_events.push(event)
    }
    { events: raw_events, consumed_event: true, done: false }
  } else {
    { events, consumed_event: true, done: false }
  }
}

///|
fn OpenAICompletionStreamDecoder::feed_line(
  self : OpenAICompletionStreamDecoder,
  raw : String,
) -> @provider_utils.DecodeBatch {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
fn OpenAICompletionStreamDecoder::flush_buffered(
  self : OpenAICompletionStreamDecoder,
) -> @provider_utils.DecodeBatch {
  match self.sse.flush() {
    Some(data) => {
      let batch = self.decode_data(data)
      if batch.done || !openai_completion_finish_known(self.finish_reason) {
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
      } else if openai_completion_finish_known(self.finish_reason) {
        { events: self.final_events(), consumed_event: false, done: true }
      } else {
        @provider_utils.DecodeBatch::empty(false)
      }
  }
}

///|
fn OpenAICompletionStreamDecoder::provider_metadata(
  self : OpenAICompletionStreamDecoder,
) -> Map[String, Json] {
  if self.logprobs.length() == 0 {
    Map([("openai", Json::empty_object())])
  } else {
    Map([("openai", ({ "logprobs": self.logprobs } : Json))])
  }
}

///|
fn OpenAICompletionStreamDecoder::response(
  self : OpenAICompletionStreamDecoder,
) -> @provider.CompletionResponse {
  @provider.CompletionResponse::new(
    self.text.to_string(),
    self.usage,
    self.finish_reason,
  ).with_diagnostics(None, self.response_metadata, self.provider_metadata(), [])
}

///|
/// Stateful decoder for legacy OpenAI completion SSE.
pub struct OpenAICompatibleCompletionStreamDecoder {
  priv sse : @http_sse.EventSourceBuffer
  priv include_raw_chunks : Bool
  priv text : StringBuilder
  priv mut usage : @moonai.Usage
  priv mut finish_reason : @moonai.FinishReason
  priv mut text_started : Bool
  priv mut finalized : Bool
}

///|
/// Create an empty completion stream decoder.
pub fn OpenAICompatibleCompletionStreamDecoder::new(
  include_raw_chunks? : Bool = false,
) -> OpenAICompatibleCompletionStreamDecoder {
  {
    sse: @http_sse.EventSourceBuffer::new(),
    include_raw_chunks,
    text: StringBuilder::new(),
    usage: @moonai.Usage::zero(),
    finish_reason: @moonai.Unknown(""),
    text_started: false,
    finalized: false,
  }
}

///|
fn OpenAICompatibleCompletionStreamDecoder::apply_json(
  self : OpenAICompatibleCompletionStreamDecoder,
  json : Json,
) -> Array[@moonai.StreamEvent] {
  let events : Array[@moonai.StreamEvent] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": value, .. } => self.usage = usage_from_json(value)
    _ => ()
  }
  match json {
    { "choices": [{ "text": String(value), .. }, ..], .. } if value != "" => {
      if !self.text_started {
        self.text_started = true
        events.push(@moonai.TextStart("text-0"))
      }
      self.text.write_string(value)
      events.push(@moonai.TextDelta(id="text-0", delta=value))
    }
    _ => ()
  }
  match json {
    { "choices": [{ "finish_reason": String(reason), .. }, ..], .. } =>
      self.finish_reason = @moonai.FinishReason::from_openai(reason)
    _ => ()
  }
  events
}

///|
fn OpenAICompatibleCompletionStreamDecoder::final_events(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> Array[@moonai.StreamEvent] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@moonai.StreamEvent] = []
  if self.text_started {
    events.push(@moonai.TextEnd("text-0"))
  }
  let reason = match self.finish_reason {
    @moonai.Unknown(_) => @moonai.Stop
    other => other
  }
  self.finish_reason = reason
  events.push(@moonai.Finish(usage=self.usage, reason~))
  events
}

///|
fn OpenAICompatibleCompletionStreamDecoder::decode_data(
  self : OpenAICompatibleCompletionStreamDecoder,
  data : String,
) -> @http_sse.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error =>
      fail(
        "OpenAI-compatible completion stream decode error: \{error}; data: \{data}",
      )
  }
  if stream_error_message(json) is Some(message) {
    let events : Array[@moonai.StreamEvent] = [@moonai.StreamError(message)]
    self.finish_reason = @moonai.Error
    for event in self.final_events() {
      events.push(event)
    }
    if self.include_raw_chunks {
      let all_events : Array[@moonai.StreamEvent] = [@moonai.Raw(json)]
      for event in events {
        all_events.push(event)
      }
      return { events: all_events, consumed_event: true, done: true }
    }
    return { events, consumed_event: true, done: true }
  }
  let events = self.apply_json(json)
  if self.include_raw_chunks {
    let all_events : Array[@moonai.StreamEvent] = [@moonai.Raw(json)]
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
) -> @http_sse.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @http_sse.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
pub fn OpenAICompatibleCompletionStreamDecoder::flush_buffered(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @http_sse.DecodeBatch raise {
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
        @http_sse.DecodeBatch::empty(true)
      } else if finish_reason_is_known(self.finish_reason) {
        { events: self.final_events(), consumed_event: false, done: true }
      } else {
        @http_sse.DecodeBatch::empty(false)
      }
  }
}

///|
/// Return the accumulated completion response.
pub fn OpenAICompatibleCompletionStreamDecoder::response(
  self : OpenAICompatibleCompletionStreamDecoder,
) -> @moonai.CompletionResponse {
  {
    text: self.text.to_string(),
    usage: self.usage,
    finish_reason: self.finish_reason,
  }
}

///|
/// Stateful decoder for OpenAI-compatible Chat Completions SSE.
pub struct OpenAICompatibleStreamDecoder {
  priv sse : @http_sse.EventSourceBuffer
  priv text : StringBuilder
  priv reasoning : StringBuilder
  priv tools : @moonai.ToolCallDeltaAssembler
  priv tool_stream_ids : Array[String]
  priv mut usage : @moonai.Usage
  priv mut finish_reason : @moonai.FinishReason
  priv mut text_started : Bool
  priv mut reasoning_started : Bool
  priv mut finalized : Bool
}

///|
/// Create an empty OpenAI-compatible stream decoder.
pub fn OpenAICompatibleStreamDecoder::new() -> OpenAICompatibleStreamDecoder {
  {
    sse: @http_sse.EventSourceBuffer::new(),
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    tools: @moonai.ToolCallDeltaAssembler::new(),
    tool_stream_ids: [],
    usage: @moonai.Usage::zero(),
    finish_reason: @moonai.Unknown(""),
    text_started: false,
    reasoning_started: false,
    finalized: false,
  }
}

///|
fn usage_from_json(json : Json) -> @moonai.Usage {
  let reasoning_tokens = match json {
    {
      "completion_tokens_details": { "reasoning_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  let cached_input_tokens = match json {
    { "prompt_tokens_details": { "cached_tokens": Number(value, ..), .. }, .. } =>
      value.to_int()
    { "prompt_cache_hit_tokens": Number(value, ..), .. } => value.to_int()
    _ => 0
  }
  {
    input_tokens: @provider_utils.json_int_field(json, "prompt_tokens"),
    output_tokens: @provider_utils.json_int_field(json, "completion_tokens"),
    total_tokens: @provider_utils.json_int_field(json, "total_tokens"),
    reasoning_tokens,
    cached_input_tokens,
  }
}

///|
fn stream_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    { "type": "error", "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn finish_reason_is_known(reason : @moonai.FinishReason) -> Bool {
  !(reason is @moonai.Unknown(""))
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
fn OpenAICompatibleStreamDecoder::apply_tool_delta(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
  fallback_index : Int,
  events : Array[@moonai.StreamEvent],
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
  let applied = self.tools.apply(
    @moonai.ToolCallDelta::new(index~, id?, name?, arguments_delta?),
  )
  self.ensure_tool_stream_id(index, applied.stream_id)
  if applied.started {
    events.push(
      @moonai.ToolInputStart(id=applied.stream_id, tool_name=applied.tool_name),
    )
  }
  if applied.arguments_delta != "" {
    events.push(
      @moonai.ToolInputDelta(
        id=applied.stream_id,
        delta=applied.arguments_delta,
      ),
    )
  }
}

///|
fn OpenAICompatibleStreamDecoder::apply_json(
  self : OpenAICompatibleStreamDecoder,
  json : Json,
) -> Array[@moonai.StreamEvent] raise {
  let events : Array[@moonai.StreamEvent] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": usage, .. } => self.usage = usage_from_json(usage)
    _ => ()
  }
  match json {
    { "choices": [{ "delta": Object(delta), .. }, ..], .. } => {
      if delta is { "content": String(content), .. } && content != "" {
        if !self.text_started {
          self.text_started = true
          events.push(@moonai.TextStart("text-0"))
        }
        self.text.write_string(content)
        events.push(@moonai.TextDelta(id="text-0", delta=content))
      }
      let reasoning = match delta {
        { "reasoning_content": String(value), .. } => value
        { "reasoning": String(value), .. } => value
        { "reasoning_delta": String(value), .. } => value
        _ => ""
      }
      if reasoning != "" {
        if !self.reasoning_started {
          self.reasoning_started = true
          events.push(@moonai.ReasoningStart("reasoning-0"))
        }
        self.reasoning.write_string(reasoning)
        events.push(@moonai.ReasoningDelta(id="reasoning-0", delta=reasoning))
      }
      if delta is { "tool_calls": Array(calls), .. } {
        for index, call in calls {
          self.apply_tool_delta(call, index, events)
        }
      }
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
fn OpenAICompatibleStreamDecoder::final_events(
  self : OpenAICompatibleStreamDecoder,
) -> Array[@moonai.StreamEvent] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@moonai.StreamEvent] = []
  if self.text_started {
    events.push(@moonai.TextEnd("text-0"))
  }
  if self.reasoning_started {
    events.push(@moonai.ReasoningEnd("reasoning-0"))
  }
  if self.finish_reason is @moonai.Error {
    for stream_id in self.tool_stream_ids {
      if stream_id != "" {
        events.push(@moonai.ToolInputEnd(stream_id))
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
      events.push(@moonai.ToolInputEnd(stream_id))
      events.push(@moonai.ToolCallReady(call))
    }
  }
  let reason = match self.finish_reason {
    @moonai.Unknown("") =>
      if self.tools.calls().length() > 0 {
        @moonai.ToolCalls
      } else {
        @moonai.Stop
      }
    other => other
  }
  self.finish_reason = reason
  events.push(@moonai.Finish(usage=self.usage, reason~))
  events
}

///|
fn OpenAICompatibleStreamDecoder::decode_data(
  self : OpenAICompatibleStreamDecoder,
  data : String,
) -> @http_sse.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error =>
      fail("OpenAI-compatible stream decode error: \{error}; data: \{data}")
  }
  if stream_error_message(json) is Some(message) {
    self.finish_reason = @moonai.Error
    let events : Array[@moonai.StreamEvent] = [@moonai.StreamError(message)]
    let terminal_events = self.final_events()
    for event in terminal_events {
      events.push(event)
    }
    return { events, consumed_event: true, done: true }
  }
  { events: self.apply_json(json), consumed_event: true, done: false }
}

///|
/// Feed one physical SSE line.
pub fn OpenAICompatibleStreamDecoder::feed_line(
  self : OpenAICompatibleStreamDecoder,
  raw : String,
) -> @http_sse.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @http_sse.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
pub fn OpenAICompatibleStreamDecoder::flush_buffered(
  self : OpenAICompatibleStreamDecoder,
) -> @http_sse.DecodeBatch raise {
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
        @http_sse.DecodeBatch::empty(true)
      } else if finish_reason_is_known(self.finish_reason) {
        { events: self.final_events(), consumed_event: false, done: true }
      } else {
        @http_sse.DecodeBatch::empty(false)
      }
  }
}

///|
/// Return the accumulated normalized response.
pub fn OpenAICompatibleStreamDecoder::response(
  self : OpenAICompatibleStreamDecoder,
) -> @moonai.ChatResponse {
  {
    text: self.text.to_string(),
    reasoning: self.reasoning.to_string(),
    tool_calls: if self.finish_reason is @moonai.Error {
      []
    } else {
      self.tools.calls()
    },
    usage: self.usage,
    finish_reason: self.finish_reason,
  }
}

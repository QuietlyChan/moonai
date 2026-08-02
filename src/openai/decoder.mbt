///|
/// Result of feeding one line or flushing one buffered SSE event.
pub(all) struct DecodeBatch {
  events : Array[@moonai.StreamEvent]
  consumed_event : Bool
  done : Bool
} derive(Debug)

///|
fn DecodeBatch::empty(done : Bool) -> DecodeBatch {
  { events: [], consumed_event: false, done }
}

///|
/// Stateful decoder for OpenAI Chat Completions SSE.
pub struct OpenAIStreamDecoder {
  priv data_lines : Array[String]
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
/// Create an empty OpenAI SSE decoder.
pub fn OpenAIStreamDecoder::new() -> OpenAIStreamDecoder {
  {
    data_lines: [],
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
fn sse_data_fragment(raw : String) -> String? {
  let line = raw.strip_suffix("\r").unwrap_or(raw)
  line.strip_prefix("data:").map(data => "\{data.trim()}")
}

///|
fn json_int(json : Json, field : String, default? : Int = 0) -> Int {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(Number(number, ..)) => number.to_int()
        _ => default
      }
    _ => default
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
    input_tokens: json_int(json, "prompt_tokens"),
    output_tokens: json_int(json, "completion_tokens"),
    total_tokens: json_int(json, "total_tokens"),
    reasoning_tokens,
    cached_input_tokens,
  }
}

///|
fn OpenAIStreamDecoder::ensure_tool_stream_id(
  self : OpenAIStreamDecoder,
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
fn OpenAIStreamDecoder::apply_tool_delta(
  self : OpenAIStreamDecoder,
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
fn OpenAIStreamDecoder::apply_json(
  self : OpenAIStreamDecoder,
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
      if delta is { "reasoning_content": String(reasoning), .. } &&
        reasoning != "" {
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
fn OpenAIStreamDecoder::final_events(
  self : OpenAIStreamDecoder,
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
  events.push(@moonai.Finish(usage=self.usage, reason=self.finish_reason))
  events
}

///|
fn OpenAIStreamDecoder::flush_event(
  self : OpenAIStreamDecoder,
) -> DecodeBatch raise {
  if self.data_lines.length() == 0 {
    return DecodeBatch::empty(self.finalized)
  }
  let data = self.data_lines.join("\n").trim().to_owned()
  self.data_lines.clear()
  if data == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => fail("OpenAI stream decode error: \{error}; data: \{data}")
  }
  { events: self.apply_json(json), consumed_event: true, done: false }
}

///|
/// Feed one physical SSE line. A blank line flushes the accumulated `data:`
/// payload; comments and other SSE fields are ignored.
pub fn OpenAIStreamDecoder::feed_line(
  self : OpenAIStreamDecoder,
  raw : String,
) -> DecodeBatch raise {
  let trimmed = raw.trim()
  if trimmed.is_empty() {
    self.flush_event()
  } else {
    if sse_data_fragment(raw) is Some(data) {
      self.data_lines.push(data)
    }
    DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated `data:` event before reporting EOF.
pub fn OpenAIStreamDecoder::flush_buffered(
  self : OpenAIStreamDecoder,
) -> DecodeBatch raise {
  self.flush_event()
}

///|
/// Return the accumulated response after the stream reaches `[DONE]`.
pub fn OpenAIStreamDecoder::response(
  self : OpenAIStreamDecoder,
) -> @moonai.ChatResponse {
  {
    text: self.text.to_string(),
    reasoning: self.reasoning.to_string(),
    tool_calls: self.tools.calls(),
    usage: self.usage,
    finish_reason: self.finish_reason,
  }
}

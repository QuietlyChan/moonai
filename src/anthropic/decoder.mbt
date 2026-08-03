///|
/// Stateful decoder for the Anthropic Messages API event stream.
pub struct AnthropicStreamDecoder {
  priv sse : @http_sse.EventSourceBuffer
  priv text : StringBuilder
  priv reasoning : StringBuilder
  priv mut input_tokens : Int
  priv mut output_tokens : Int
  priv mut cache_creation_input_tokens : Int
  priv mut cache_read_input_tokens : Int
  priv mut reasoning_tokens : Int
  priv mut finish_reason : @moonai.FinishReason
  priv block_kinds : Array[String]
  priv block_ids : Array[String]
  priv block_names : Array[String]
  priv block_data : Array[StringBuilder]
  priv block_started : Array[Bool]
  priv block_stopped : Array[Bool]
  priv block_ready : Array[Bool]
  priv tool_calls : Array[@moonai.ToolCall]
  priv mut finalized : Bool
}

///|
/// Create an empty Anthropic SSE decoder.
pub fn AnthropicStreamDecoder::new() -> AnthropicStreamDecoder {
  {
    sse: @http_sse.EventSourceBuffer::new(),
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    input_tokens: 0,
    output_tokens: 0,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    reasoning_tokens: 0,
    finish_reason: @moonai.Unknown(""),
    block_kinds: [],
    block_ids: [],
    block_names: [],
    block_data: [],
    block_started: [],
    block_stopped: [],
    block_ready: [],
    tool_calls: [],
    finalized: false,
  }
}

///|
fn AnthropicStreamDecoder::ensure_block(
  self : AnthropicStreamDecoder,
  index : Int,
) -> Unit raise {
  guard index >= 0 else {
    fail("Anthropic content block index must be non-negative")
  }
  while self.block_kinds.length() <= index {
    self.block_kinds.push("")
    self.block_ids.push("")
    self.block_names.push("")
    self.block_data.push(StringBuilder::new())
    self.block_started.push(false)
    self.block_stopped.push(false)
    self.block_ready.push(false)
  }
}

///|
fn AnthropicStreamDecoder::block_id(
  self : AnthropicStreamDecoder,
  index : Int,
  kind : String,
) -> String {
  if self.block_ids[index] != "" {
    self.block_ids[index]
  } else {
    "\{kind}-\{index}"
  }
}

///|
fn AnthropicStreamDecoder::start_text_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@moonai.StreamEvent],
) -> Unit {
  if !self.block_started[index] {
    self.block_started[index] = true
    events.push(@moonai.TextStart(self.block_id(index, "text")))
  }
}

///|
fn AnthropicStreamDecoder::start_reasoning_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@moonai.StreamEvent],
) -> Unit {
  if !self.block_started[index] {
    self.block_started[index] = true
    events.push(@moonai.ReasoningStart(self.block_id(index, "reasoning")))
  }
}

///|
fn AnthropicStreamDecoder::start_tool_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@moonai.StreamEvent],
) -> Unit {
  if !self.block_started[index] {
    self.block_started[index] = true
    let id = self.block_id(index, "tool")
    let name = if self.block_names[index] == "" {
      "tool-\{index}"
    } else {
      self.block_names[index]
    }
    events.push(@moonai.ToolInputStart(id~, tool_name=name))
  }
}

///|
fn AnthropicStreamDecoder::finish_tool_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@moonai.StreamEvent],
) -> Unit raise {
  if self.block_ready[index] {
    return
  }
  let id = self.block_id(index, "tool")
  let name = if self.block_names[index] == "" {
    "tool-\{index}"
  } else {
    self.block_names[index]
  }
  let raw = self.block_data[index].to_string()
  let arguments = if raw.trim().is_empty() { "{}" } else { raw }
  let parsed = @json.parse(arguments) catch {
    error =>
      fail("Anthropic tool call \'{name}\' has invalid JSON input: \{error}")
  }
  guard parsed is Object(_) else {
    fail("Anthropic tool call \'{name}\' input must be a JSON object")
  }
  let call = @moonai.ToolCall::new(id~, name~, arguments~)
  self.tool_calls.push(call)
  self.block_ready[index] = true
  events.push(@moonai.ToolCallReady(call))
}

///|
fn AnthropicStreamDecoder::finish_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@moonai.StreamEvent],
) -> Unit raise {
  if self.block_stopped[index] {
    return
  }
  let kind = self.block_kinds[index]
  if kind == "text" {
    if self.block_started[index] {
      events.push(@moonai.TextEnd(self.block_id(index, "text")))
    }
  } else if kind == "thinking" {
    if self.block_started[index] {
      events.push(@moonai.ReasoningEnd(self.block_id(index, "reasoning")))
    }
  } else if kind == "tool_use" {
    if !self.block_started[index] {
      self.start_tool_block(index, events)
    }
    events.push(@moonai.ToolInputEnd(self.block_id(index, "tool")))
    self.finish_tool_block(index, events)
  }
  self.block_stopped[index] = true
}

///|
fn AnthropicStreamDecoder::apply_usage(
  self : AnthropicStreamDecoder,
  usage : Json,
) -> Unit {
  if @provider_utils.json_int_field_opt(usage, "input_tokens") is Some(value) {
    self.input_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "output_tokens") is Some(value) {
    self.output_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "cache_creation_input_tokens")
    is Some(value) {
    self.cache_creation_input_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "cache_read_input_tokens")
    is Some(value) {
    self.cache_read_input_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "thinking_tokens") is Some(value) {
    self.reasoning_tokens = value
  } else if @provider_utils.json_int_field_opt(usage, "reasoning_tokens")
    is Some(value) {
    self.reasoning_tokens = value
  } else {
    match usage {
      {
        "output_tokens_details": { "thinking_tokens": Number(value, ..), .. },
        ..
      } => self.reasoning_tokens = value.to_int()
      _ => ()
    }
  }
}

///|
fn map_stop_reason(value : String) -> @moonai.FinishReason {
  match value {
    "end_turn" | "stop_sequence" | "pause_turn" => @moonai.Stop
    "tool_use" => @moonai.ToolCalls
    "max_tokens" | "model_context_window_exceeded" => @moonai.Length
    "refusal" => @moonai.ContentFilter
    "error" => @moonai.Error
    other => @moonai.Unknown(other)
  }
}

///|
fn AnthropicStreamDecoder::usage(
  self : AnthropicStreamDecoder,
) -> @moonai.Usage {
  let input = self.input_tokens +
    self.cache_creation_input_tokens +
    self.cache_read_input_tokens
  {
    input_tokens: input,
    output_tokens: self.output_tokens,
    total_tokens: input + self.output_tokens,
    reasoning_tokens: self.reasoning_tokens,
    cached_input_tokens: self.cache_read_input_tokens,
  }
}

///|
fn AnthropicStreamDecoder::final_events(
  self : AnthropicStreamDecoder,
) -> Array[@moonai.StreamEvent] raise {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@moonai.StreamEvent] = []
  for index, kind in self.block_kinds {
    if kind == "text" {
      if self.block_started[index] && !self.block_stopped[index] {
        events.push(@moonai.TextEnd(self.block_id(index, "text")))
        self.block_stopped[index] = true
      }
    } else if kind == "thinking" {
      if self.block_started[index] && !self.block_stopped[index] {
        events.push(@moonai.ReasoningEnd(self.block_id(index, "reasoning")))
        self.block_stopped[index] = true
      }
    } else if kind == "tool_use" {
      if !self.block_started[index] {
        self.start_tool_block(index, events)
      }
      if !self.block_stopped[index] {
        events.push(@moonai.ToolInputEnd(self.block_id(index, "tool")))
        self.block_stopped[index] = true
      }
      if !(self.finish_reason is @moonai.Error) {
        self.finish_tool_block(index, events)
      }
    }
  }
  let reason = match self.finish_reason {
    @moonai.Unknown("") =>
      if self.tool_calls.length() > 0 {
        @moonai.ToolCalls
      } else {
        @moonai.Stop
      }
    other => other
  }
  self.finish_reason = reason
  events.push(@moonai.Finish(usage=self.usage(), reason~))
  events
}

///|
fn AnthropicStreamDecoder::apply_json(
  self : AnthropicStreamDecoder,
  json : Json,
) -> (Array[@moonai.StreamEvent], Bool) raise {
  let events : Array[@moonai.StreamEvent] = []
  let event_type = @provider_utils.json_string_field(json, "type").unwrap_or("")
  match event_type {
    "message_start" => {
      match json {
        { "message": { "usage": usage, "stop_reason": String(reason), .. }, .. } => {
          self.apply_usage(usage)
          self.finish_reason = map_stop_reason(reason)
        }
        { "message": { "usage": usage, .. }, .. } => self.apply_usage(usage)
        { "message": { "stop_reason": String(reason), .. }, .. } =>
          self.finish_reason = map_stop_reason(reason)
        _ => ()
      }
      (events, false)
    }
    "content_block_start" => {
      match json {
        { "index": Number(index, ..), "content_block": Object(block), .. } => {
          let i = index.to_int()
          self.ensure_block(i)
          let kind = match block.get("type") {
            Some(String(value)) => value
            _ => ""
          }
          self.block_kinds[i] = kind
          if block.get("id") is Some(String(id)) {
            self.block_ids[i] = id
          }
          if block.get("name") is Some(String(name)) {
            self.block_names[i] = name
          }
          if kind == "text" {
            self.start_text_block(i, events)
          } else if kind == "thinking" {
            self.start_reasoning_block(i, events)
          } else if kind == "tool_use" {
            self.start_tool_block(i, events)
          }
        }
        _ => ()
      }
      (events, false)
    }
    "content_block_delta" => {
      match json {
        { "index": Number(index, ..), "delta": Object(delta), .. } => {
          let i = index.to_int()
          self.ensure_block(i)
          let delta_type = match delta.get("type") {
            Some(String(value)) => value
            _ => ""
          }
          if delta_type == "text_delta" {
            let value = match delta.get("text") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              self.block_kinds[i] = "text"
              self.start_text_block(i, events)
              self.text.write_string(value)
              events.push(
                @moonai.TextDelta(id=self.block_id(i, "text"), delta=value),
              )
            }
          } else if delta_type == "thinking_delta" {
            let value = match delta.get("thinking") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              self.block_kinds[i] = "thinking"
              self.start_reasoning_block(i, events)
              self.reasoning.write_string(value)
              events.push(
                @moonai.ReasoningDelta(
                  id=self.block_id(i, "reasoning"),
                  delta=value,
                ),
              )
            }
          } else if delta_type == "input_json_delta" {
            let value = match delta.get("partial_json") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              self.block_kinds[i] = "tool_use"
              self.start_tool_block(i, events)
              self.block_data[i].write_string(value)
              events.push(
                @moonai.ToolInputDelta(id=self.block_id(i, "tool"), delta=value),
              )
            }
          } else if delta_type != "signature_delta" {
            events.push(@moonai.Raw(json))
          }
        }
        _ => ()
      }
      (events, false)
    }
    "content_block_stop" => {
      match json {
        { "index": Number(index, ..), .. } => {
          let i = index.to_int()
          self.ensure_block(i)
          self.finish_block(i, events)
        }
        _ => ()
      }
      (events, false)
    }
    "message_delta" => {
      match json {
        { "delta": Object(delta), "usage": usage, .. } => {
          self.apply_usage(usage)
          if delta.get("stop_reason") is Some(String(reason)) {
            self.finish_reason = map_stop_reason(reason)
          }
        }
        { "delta": Object(delta), .. } =>
          if delta.get("stop_reason") is Some(String(reason)) {
            self.finish_reason = map_stop_reason(reason)
          }
        { "usage": usage, .. } => self.apply_usage(usage)
        _ => ()
      }
      (events, false)
    }
    "message_stop" => (self.final_events(), true)
    "error" => {
      let message = match json {
        { "error": Object(error), .. } =>
          match error.get("message") {
            Some(String(value)) => value
            _ => json.stringify()
          }
        _ => json.stringify()
      }
      self.finish_reason = @moonai.Error
      events.push(@moonai.StreamError(message))
      let final_events = self.final_events()
      for event in final_events {
        events.push(event)
      }
      (events, true)
    }
    "ping" => (events, false)
    _ => {
      events.push(@moonai.Raw(json))
      (events, false)
    }
  }
}

///|
fn AnthropicStreamDecoder::decode_data(
  self : AnthropicStreamDecoder,
  data : String,
) -> @http_sse.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => fail("Anthropic stream decode error: \{error}; data: \{data}")
  }
  let (events, done) = self.apply_json(json)
  { events, consumed_event: true, done }
}

///|
/// Feed one physical SSE line. A blank line flushes the accumulated `data:`
/// payload; comments and other SSE fields are ignored.
pub fn AnthropicStreamDecoder::feed_line(
  self : AnthropicStreamDecoder,
  raw : String,
) -> @http_sse.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @http_sse.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated `data:` event before reporting EOF.
pub fn AnthropicStreamDecoder::flush_buffered(
  self : AnthropicStreamDecoder,
) -> @http_sse.DecodeBatch raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @http_sse.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Return the accumulated response after the stream reaches `message_stop`.
pub fn AnthropicStreamDecoder::response(
  self : AnthropicStreamDecoder,
) -> @moonai.ChatResponse {
  let reason = match self.finish_reason {
    @moonai.Unknown(value) if value == "" && self.tool_calls.length() > 0 =>
      @moonai.ToolCalls
    other => other
  }
  {
    text: self.text.to_string(),
    reasoning: self.reasoning.to_string(),
    tool_calls: self.tool_calls,
    usage: self.usage(),
    finish_reason: reason,
  }
}

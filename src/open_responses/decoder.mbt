///|
/// Stateful decoder for Open Responses SSE events.
pub struct OpenResponsesStreamDecoder {
  priv sse : @http_sse.EventSourceBuffer
  priv text : StringBuilder
  priv reasoning : StringBuilder
  priv text_ids : Array[String]
  priv text_stopped : Array[Bool]
  priv reasoning_ids : Array[String]
  priv reasoning_stopped : Array[Bool]
  priv tool_item_ids : Array[String]
  priv tool_call_ids : Array[String]
  priv tool_names : Array[String]
  priv tool_arguments : Array[String]
  priv tool_started : Array[Bool]
  priv tool_ready : Array[Bool]
  priv tool_calls : Array[@moonai.ToolCall]
  priv mut usage : @moonai.Usage
  priv mut finish_reason : @moonai.FinishReason
  priv mut finalized : Bool
}

///|
/// Create an empty Open Responses stream decoder.
pub fn OpenResponsesStreamDecoder::new() -> OpenResponsesStreamDecoder {
  {
    sse: @http_sse.EventSourceBuffer::new(),
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    text_ids: [],
    text_stopped: [],
    reasoning_ids: [],
    reasoning_stopped: [],
    tool_item_ids: [],
    tool_call_ids: [],
    tool_names: [],
    tool_arguments: [],
    tool_started: [],
    tool_ready: [],
    tool_calls: [],
    usage: @moonai.Usage::zero(),
    finish_reason: @moonai.Unknown(""),
    finalized: false,
  }
}

///|
fn find_id(values : Array[String], id : String) -> Int? {
  for index, value in values {
    if value == id {
      return Some(index)
    }
  }
  None
}

///|
fn OpenResponsesStreamDecoder::start_text(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@moonai.StreamEvent],
) -> Int {
  match find_id(self.text_ids, id) {
    Some(index) => index
    None => {
      self.text_ids.push(id)
      self.text_stopped.push(false)
      events.push(@moonai.TextStart(id))
      self.text_ids.length() - 1
    }
  }
}

///|
fn OpenResponsesStreamDecoder::finish_text(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@moonai.StreamEvent],
) -> Unit {
  let index = self.start_text(id, events)
  if !self.text_stopped[index] {
    self.text_stopped[index] = true
    events.push(@moonai.TextEnd(id))
  }
}

///|
fn OpenResponsesStreamDecoder::start_reasoning(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@moonai.StreamEvent],
) -> Int {
  match find_id(self.reasoning_ids, id) {
    Some(index) => index
    None => {
      self.reasoning_ids.push(id)
      self.reasoning_stopped.push(false)
      events.push(@moonai.ReasoningStart(id))
      self.reasoning_ids.length() - 1
    }
  }
}

///|
fn OpenResponsesStreamDecoder::finish_reasoning(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@moonai.StreamEvent],
) -> Unit {
  let index = self.start_reasoning(id, events)
  if !self.reasoning_stopped[index] {
    self.reasoning_stopped[index] = true
    events.push(@moonai.ReasoningEnd(id))
  }
}

///|
fn OpenResponsesStreamDecoder::ensure_tool(
  self : OpenResponsesStreamDecoder,
  item_id : String,
) -> Int {
  match find_id(self.tool_item_ids, item_id) {
    Some(index) => index
    None => {
      self.tool_item_ids.push(item_id)
      self.tool_call_ids.push("")
      self.tool_names.push("")
      self.tool_arguments.push("")
      self.tool_started.push(false)
      self.tool_ready.push(false)
      self.tool_item_ids.length() - 1
    }
  }
}

///|
fn OpenResponsesStreamDecoder::update_tool_from_item(
  self : OpenResponsesStreamDecoder,
  item : Json,
) -> Int {
  let item_id = @provider_utils.json_string_field(item, "id").unwrap_or(
    "tool-item-0",
  )
  let index = self.ensure_tool(item_id)
  if @provider_utils.json_string_field(item, "call_id") is Some(value) {
    self.tool_call_ids[index] = value
  }
  if @provider_utils.json_string_field(item, "name") is Some(value) {
    self.tool_names[index] = value
  }
  if @provider_utils.json_string_field(item, "arguments") is Some(value) &&
    value != "" {
    self.tool_arguments[index] = value
  }
  index
}

///|
fn OpenResponsesStreamDecoder::tool_id(
  self : OpenResponsesStreamDecoder,
  index : Int,
) -> String {
  if self.tool_call_ids[index] == "" {
    self.tool_item_ids[index]
  } else {
    self.tool_call_ids[index]
  }
}

///|
fn OpenResponsesStreamDecoder::start_tool(
  self : OpenResponsesStreamDecoder,
  index : Int,
  events : Array[@moonai.StreamEvent],
) -> Unit {
  if !self.tool_started[index] {
    self.tool_started[index] = true
    let name = if self.tool_names[index] == "" {
      "tool-\{index}"
    } else {
      self.tool_names[index]
    }
    events.push(@moonai.ToolInputStart(id=self.tool_id(index), tool_name=name))
  }
}

///|
fn OpenResponsesStreamDecoder::finish_tool(
  self : OpenResponsesStreamDecoder,
  index : Int,
  events : Array[@moonai.StreamEvent],
) -> Unit raise {
  if self.tool_ready[index] {
    return
  }
  self.start_tool(index, events)
  let id = self.tool_id(index)
  let name = if self.tool_names[index] == "" {
    "tool-\{index}"
  } else {
    self.tool_names[index]
  }
  let arguments = if self.tool_arguments[index].trim().is_empty() {
    "{}"
  } else {
    self.tool_arguments[index]
  }
  let parsed = @json.parse(arguments) catch {
    error =>
      fail("Open Responses tool call \'\{name}\' has invalid JSON: \{error}")
  }
  guard parsed is Object(_) else {
    fail("Open Responses tool call \'\{name}\' input must be a JSON object")
  }
  let call = @moonai.ToolCall::new(id~, name~, arguments~)
  self.tool_calls.push(call)
  self.tool_ready[index] = true
  events.push(@moonai.ToolInputEnd(id))
  events.push(@moonai.ToolCallReady(call))
}

///|
fn usage_from_json(json : Json) -> @moonai.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "input_tokens")
  let output_tokens = @provider_utils.json_int_field(json, "output_tokens")
  let total_tokens = @provider_utils.json_int_field(
    json,
    "total_tokens",
    default=input_tokens + output_tokens,
  )
  let cached_input_tokens = match json {
    { "input_tokens_details": { "cached_tokens": Number(value, ..), .. }, .. } =>
      value.to_int()
    _ => 0
  }
  let reasoning_tokens = match json {
    {
      "output_tokens_details": { "reasoning_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  {
    input_tokens,
    output_tokens,
    total_tokens,
    reasoning_tokens,
    cached_input_tokens,
  }
}

///|
fn map_finish_reason(
  reason : String,
  has_tool_calls : Bool,
) -> @moonai.FinishReason {
  match reason {
    "" => if has_tool_calls { @moonai.ToolCalls } else { @moonai.Stop }
    "max_output_tokens" => @moonai.Length
    "content_filter" => @moonai.ContentFilter
    other =>
      if has_tool_calls {
        @moonai.ToolCalls
      } else {
        @moonai.Unknown(other)
      }
  }
}

///|
fn OpenResponsesStreamDecoder::apply_response_state(
  self : OpenResponsesStreamDecoder,
  event_type : String,
  response : Json,
  events : Array[@moonai.StreamEvent],
) -> Unit {
  match response {
    { "usage": usage, .. } if !(usage is Null) =>
      self.usage = usage_from_json(usage)
    _ => ()
  }
  let reason = match response {
    { "incomplete_details": { "reason": String(value), .. }, .. } => value
    _ => ""
  }
  if event_type == "response.failed" {
    self.finish_reason = @moonai.Error
    let message = match response {
      { "error": { "message": String(value), .. }, .. } => value
      _ => "Open Responses request failed"
    }
    events.push(@moonai.StreamError(message))
  } else {
    self.finish_reason = map_finish_reason(
      reason,
      self.tool_item_ids.length() > 0,
    )
  }
}

///|
fn OpenResponsesStreamDecoder::apply_json(
  self : OpenResponsesStreamDecoder,
  json : Json,
) -> (Array[@moonai.StreamEvent], Bool) raise {
  let events : Array[@moonai.StreamEvent] = []
  let mut done = false
  let event_type = @provider_utils.json_string_field(json, "type").unwrap_or("")
  match event_type {
    "response.output_item.added" =>
      match json {
        { "item": Object(item), .. } => {
          let kind = match item.get("type") {
            Some(String(value)) => value
            _ => ""
          }
          let id = match item.get("id") {
            Some(String(value)) => value
            _ => "item-0"
          }
          if kind == "message" {
            let _ = self.start_text(id, events)
          } else if kind == "reasoning" {
            let _ = self.start_reasoning(id, events)
          } else if kind == "function_call" {
            let index = self.update_tool_from_item(Json::object(item))
            self.start_tool(index, events)
          }
        }
        _ => ()
      }
    "response.output_text.delta" | "response.refusal.delta" => {
      let id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "text-0",
      )
      let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
      let _ = self.start_text(id, events)
      if delta != "" {
        self.text.write_string(delta)
        events.push(@moonai.TextDelta(id~, delta~))
      }
    }
    "response.output_text.done" | "response.refusal.done" => {
      let id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "text-0",
      )
      self.finish_text(id, events)
    }
    "response.reasoning_text.delta" | "response.reasoning_summary_text.delta" => {
      let id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "reasoning-0",
      )
      let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
      let _ = self.start_reasoning(id, events)
      if delta != "" {
        self.reasoning.write_string(delta)
        events.push(@moonai.ReasoningDelta(id~, delta~))
      }
    }
    "response.reasoning_text.done" | "response.reasoning_summary_text.done" => {
      let id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "reasoning-0",
      )
      self.finish_reasoning(id, events)
    }
    "response.function_call_arguments.delta" => {
      let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "tool-item-0",
      )
      let index = self.ensure_tool(item_id)
      if @provider_utils.json_string_field(json, "call_id") is Some(value) {
        self.tool_call_ids[index] = value
      }
      self.start_tool(index, events)
      let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
      if delta != "" {
        self.tool_arguments[index] = self.tool_arguments[index] + delta
        events.push(@moonai.ToolInputDelta(id=self.tool_id(index), delta~))
      }
    }
    "response.function_call_arguments.done" => {
      let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "tool-item-0",
      )
      let index = self.ensure_tool(item_id)
      if @provider_utils.json_string_field(json, "arguments") is Some(value) {
        self.tool_arguments[index] = value
      }
    }
    "response.output_item.done" =>
      match json {
        { "item": Object(item), .. } => {
          let kind = match item.get("type") {
            Some(String(value)) => value
            _ => ""
          }
          let id = match item.get("id") {
            Some(String(value)) => value
            _ => "item-0"
          }
          if kind == "message" {
            self.finish_text(id, events)
          } else if kind == "reasoning" {
            self.finish_reasoning(id, events)
          } else if kind == "function_call" {
            let index = self.update_tool_from_item(Json::object(item))
            self.finish_tool(index, events)
          }
        }
        _ => ()
      }
    "response.completed" | "response.incomplete" | "response.failed" => {
      match json {
        { "response": response, .. } =>
          self.apply_response_state(event_type, response, events)
        _ => ()
      }
      let terminal_events = self.final_events()
      for event in terminal_events {
        events.push(event)
      }
      done = true
    }
    "error" => {
      let message = match json {
        { "error": { "message": String(value), .. }, .. } => value
        _ => json.stringify()
      }
      self.finish_reason = @moonai.Error
      events.push(@moonai.StreamError(message))
      let terminal_events = self.final_events()
      for event in terminal_events {
        events.push(event)
      }
      done = true
    }
    _ => ()
  }
  (events, done)
}

///|
fn OpenResponsesStreamDecoder::final_events(
  self : OpenResponsesStreamDecoder,
) -> Array[@moonai.StreamEvent] raise {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@moonai.StreamEvent] = []
  for index, id in self.text_ids {
    if !self.text_stopped[index] {
      self.text_stopped[index] = true
      events.push(@moonai.TextEnd(id))
    }
  }
  for index, id in self.reasoning_ids {
    if !self.reasoning_stopped[index] {
      self.reasoning_stopped[index] = true
      events.push(@moonai.ReasoningEnd(id))
    }
  }
  for index, _ in self.tool_item_ids {
    if self.finish_reason is @moonai.Error {
      if self.tool_started[index] && !self.tool_ready[index] {
        events.push(@moonai.ToolInputEnd(self.tool_id(index)))
      }
    } else {
      self.finish_tool(index, events)
    }
  }
  let reason = match self.finish_reason {
    @moonai.Unknown(value) if value == "" =>
      if self.tool_calls.length() > 0 {
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
fn OpenResponsesStreamDecoder::decode_data(
  self : OpenResponsesStreamDecoder,
  data : String,
) -> @http_sse.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => fail("Open Responses stream decode error: \{error}; data: \{data}")
  }
  let (events, done) = self.apply_json(json)
  { events, consumed_event: true, done }
}

///|
/// Feed one physical SSE line.
pub fn OpenResponsesStreamDecoder::feed_line(
  self : OpenResponsesStreamDecoder,
  raw : String,
) -> @http_sse.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @http_sse.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
pub fn OpenResponsesStreamDecoder::flush_buffered(
  self : OpenResponsesStreamDecoder,
) -> @http_sse.DecodeBatch raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @http_sse.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Return the accumulated normalized response.
pub fn OpenResponsesStreamDecoder::response(
  self : OpenResponsesStreamDecoder,
) -> @moonai.ChatResponse {
  {
    text: self.text.to_string(),
    reasoning: self.reasoning.to_string(),
    tool_calls: self.tool_calls,
    usage: self.usage,
    finish_reason: self.finish_reason,
  }
}

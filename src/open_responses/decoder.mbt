///|
enum ResponsesContentRef {
  ResponsesText(Int)
  ResponsesReasoning(Int)
  ResponsesTool(Int)
}

///|
/// Stateful decoder for Open Responses SSE events.
pub struct OpenResponsesStreamDecoder {
  priv sse : @provider_utils.EventSourceBuffer
  priv include_raw_chunks : Bool
  priv progressive_tool_calls : Bool
  priv emit_failed_error : Bool
  priv text : StringBuilder
  priv reasoning : StringBuilder
  priv text_parts : Array[StringBuilder]
  priv reasoning_parts : Array[StringBuilder]
  priv content_order : Array[ResponsesContentRef]
  priv text_ids : Array[String]
  priv text_stopped : Array[Bool]
  priv reasoning_ids : Array[String]
  priv reasoning_stopped : Array[Bool]
  priv tool_item_ids : Array[String]
  priv tool_call_ids : Array[String]
  priv tool_stream_ids : Array[String]
  priv tool_names : Array[String]
  priv tool_arguments : Array[String]
  priv tool_emitted_arguments : Array[String]
  priv tool_started : Array[Bool]
  priv tool_ready : Array[Bool]
  priv tool_calls : Array[@provider.ToolCall]
  priv mut usage : @provider.Usage
  priv mut raw_usage : Json?
  priv mut finish_reason : @provider.FinishReason
  priv mut finish_reason_raw : String?
  priv provider_name : String
  priv generate_id : @provider_utils.IdGenerator
  priv observe_json : (Json) -> Unit
  priv validate_json : ((Json) -> Unit raise)?
  priv observe_events : (Json) -> Array[@provider.StreamEvent]
  priv build_provider_metadata : () -> Map[String, Json]
  priv build_content : () -> Array[@provider.GeneratedContent]
  priv use_built_content : Bool
  priv has_extra_tool_calls : () -> Bool
  priv mut response_metadata : @provider.ResponseMetadata?
  priv mut provider_metadata : Map[String, Json]
  priv mut finalized : Bool
}

///|
/// Create an empty Open Responses stream decoder.
pub fn OpenResponsesStreamDecoder::new(
  include_raw_chunks? : Bool = false,
  progressive_tool_calls? : Bool = false,
  emit_failed_error? : Bool = false,
  provider_name? : String = "",
  id_generator? : @provider_utils.IdGenerator,
  observe_json? : (Json) -> Unit = ignore_responses_json,
  validate_json? : (Json) -> Unit raise,
  observe_events? : (Json) -> Array[@provider.StreamEvent] = empty_responses_events,
  build_provider_metadata? : () -> Map[String, Json] = empty_responses_metadata,
  build_content? : () -> Array[@provider.GeneratedContent] = empty_responses_content,
  use_built_content? : Bool = false,
  has_extra_tool_calls? : () -> Bool = no_extra_responses_tool_calls,
) -> OpenResponsesStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    progressive_tool_calls,
    emit_failed_error,
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    text_parts: [],
    reasoning_parts: [],
    content_order: [],
    text_ids: [],
    text_stopped: [],
    reasoning_ids: [],
    reasoning_stopped: [],
    tool_item_ids: [],
    tool_call_ids: [],
    tool_stream_ids: [],
    tool_names: [],
    tool_arguments: [],
    tool_emitted_arguments: [],
    tool_started: [],
    tool_ready: [],
    tool_calls: [],
    usage: @provider.Usage::zero(),
    raw_usage: None,
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    provider_name,
    generate_id: id_generator.unwrap_or(@provider_utils.generate_id),
    observe_json,
    validate_json,
    observe_events,
    build_provider_metadata,
    build_content,
    use_built_content,
    has_extra_tool_calls,
    response_metadata: None,
    provider_metadata: Map([]),
    finalized: false,
  }
}

///|
fn ignore_responses_json(_json : Json) -> Unit {
  ()
}

///|
fn empty_responses_events(_json : Json) -> Array[@provider.StreamEvent] {
  []
}

///|
fn empty_responses_content() -> Array[@provider.GeneratedContent] {
  []
}

///|
fn no_extra_responses_tool_calls() -> Bool {
  false
}

///|
fn OpenResponsesStreamDecoder::has_provider_extension_tool_calls(
  self : OpenResponsesStreamDecoder,
) -> Bool {
  if (self.has_extra_tool_calls)() {
    return true
  }
  if !self.use_built_content {
    return false
  }
  for part in (self.build_content)() {
    match part {
      @provider.GeneratedToolCallOutput(call) if !call.provider_executed =>
        return true
      _ => ()
    }
  }
  false
}

///|
fn empty_responses_metadata() -> Map[String, Json] {
  Map([])
}

///|
/// Retain identity and provider-specific fields carried by stream chunks.
fn OpenResponsesStreamDecoder::record_json(
  self : OpenResponsesStreamDecoder,
  json : Json,
) -> Unit {
  let chunk_metadata = @provider.ResponseMetadata::from_json(json)
  if !chunk_metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, chunk_metadata),
    )
  }
  if self.provider_name != "" {
    self.provider_metadata = @provider.merge_provider_metadata(
      self.provider_metadata,
      @provider_utils.provider_metadata_from_json(json, self.provider_name),
    )
  }
  match json {
    { "response": Object(response), .. } =>
      self.record_json(Json::object(response))
    _ => ()
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
/// OpenAI Responses identifies reasoning summary parts by the parent item and
/// summary index. Keep those parts separate in the normalized stream so a
/// later summary does not merge into the previous one.
fn reasoning_summary_id(json : Json) -> String {
  let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
    "reasoning-0",
  )
  let summary_index = @provider_utils.json_int_field(json, "summary_index")
  "\{item_id}:\{summary_index}"
}

///|
/// Prefer the summary-part identity when the output item has already opened
/// the first summary part. This keeps legacy reasoning events usable while
/// avoiding a second `item_id` stream for summary text.
fn OpenResponsesStreamDecoder::reasoning_event_id(
  self : OpenResponsesStreamDecoder,
  item_id : String,
) -> String {
  let first_summary_id = "\{item_id}:0"
  if find_id(self.reasoning_ids, first_summary_id) is Some(_) {
    first_summary_id
  } else {
    item_id
  }
}

///|
fn OpenResponsesStreamDecoder::start_text(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@provider.StreamEvent],
) -> Int {
  match find_id(self.text_ids, id) {
    Some(index) => index
    None => {
      self.text_ids.push(id)
      self.text_stopped.push(false)
      self.text_parts.push(StringBuilder::new())
      self.content_order.push(ResponsesText(self.text_ids.length() - 1))
      events.push(@provider.TextStart(id))
      self.text_ids.length() - 1
    }
  }
}

///|
fn OpenResponsesStreamDecoder::finish_text(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let index = self.start_text(id, events)
  if !self.text_stopped[index] {
    self.text_stopped[index] = true
    events.push(@provider.TextEnd(id))
  }
}

///|
fn OpenResponsesStreamDecoder::start_reasoning(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@provider.StreamEvent],
) -> Int {
  match find_id(self.reasoning_ids, id) {
    Some(index) => index
    None => {
      self.reasoning_ids.push(id)
      self.reasoning_stopped.push(false)
      self.reasoning_parts.push(StringBuilder::new())
      self.content_order.push(
        ResponsesReasoning(self.reasoning_ids.length() - 1),
      )
      events.push(@provider.ReasoningStart(id))
      self.reasoning_ids.length() - 1
    }
  }
}

///|
fn OpenResponsesStreamDecoder::finish_reasoning(
  self : OpenResponsesStreamDecoder,
  id : String,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let index = self.start_reasoning(id, events)
  if !self.reasoning_stopped[index] {
    self.reasoning_stopped[index] = true
    events.push(@provider.ReasoningEnd(id))
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
      self.tool_stream_ids.push("")
      self.tool_names.push("")
      self.tool_arguments.push("")
      self.tool_emitted_arguments.push("")
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
  self.tool_stream_id(index)
}

///|
fn OpenResponsesStreamDecoder::tool_stream_id(
  self : OpenResponsesStreamDecoder,
  index : Int,
) -> String {
  if self.tool_stream_ids[index] == "" {
    self.tool_stream_ids[index] = if self.tool_call_ids[index] != "" {
      self.tool_call_ids[index]
    } else {
      let generated = (self.generate_id)()
      if generated == "" {
        "tool-{index}"
      } else {
        generated
      }
    }
  }
  self.tool_stream_ids[index]
}

///|
fn OpenResponsesStreamDecoder::start_tool(
  self : OpenResponsesStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if !self.tool_started[index] {
    self.tool_started[index] = true
    let name = if self.tool_names[index] == "" {
      "tool-\{index}"
    } else {
      self.tool_names[index]
    }
    events.push(
      @provider.ToolInputStart(id=self.tool_stream_id(index), tool_name=name),
    )
  }
}

///|
fn OpenResponsesStreamDecoder::emit_complete_tool_arguments_if_unseen(
  self : OpenResponsesStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let arguments = self.tool_arguments[index]
  if arguments != "" && self.tool_emitted_arguments[index] == "" {
    self.tool_emitted_arguments[index] = arguments
    events.push(
      @provider.ToolInputDelta(id=self.tool_stream_id(index), delta=arguments),
    )
  }
}

///|
fn OpenResponsesStreamDecoder::finish_tool(
  self : OpenResponsesStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if self.tool_ready[index] {
    return
  }
  if self.progressive_tool_calls {
    self.start_tool(index, events)
    self.emit_complete_tool_arguments_if_unseen(index, events)
  }
  let id = self.tool_id(index)
  let name = if self.tool_names[index] == "" {
    "tool-\{index}"
  } else {
    self.tool_names[index]
  }
  let arguments = self.tool_arguments[index]
  let call = @provider.ToolCall::new(id~, name~, arguments~)
  let call_index = self.tool_calls.length()
  self.tool_calls.push(call)
  self.content_order.push(ResponsesTool(call_index))
  self.tool_ready[index] = true
  if self.progressive_tool_calls {
    events.push(@provider.ToolInputEnd(self.tool_stream_id(index)))
  }
  events.push(@provider.ToolCallReady(call))
}

///|
fn usage_from_json(json : Json) -> @provider.Usage {
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
  let cache_write_input_tokens = match json {
    {
      "input_tokens_details": { "cache_write_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
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
    cache_write_input_tokens,
  }
}

///|
fn map_finish_reason(
  reason : String,
  has_tool_calls : Bool,
) -> @provider.FinishReason {
  match reason {
    "" => if has_tool_calls { @provider.ToolCalls } else { @provider.Stop }
    "max_output_tokens" => @provider.Length
    "content_filter" => @provider.ContentFilter
    other =>
      if has_tool_calls {
        @provider.ToolCalls
      } else {
        @provider.Unknown(other)
      }
  }
}

///|
fn OpenResponsesStreamDecoder::apply_response_state(
  self : OpenResponsesStreamDecoder,
  event_type : String,
  response : Json,
  events : Array[@provider.StreamEvent],
) -> Unit {
  match response {
    { "usage": usage, .. } if !(usage is Null) => {
      self.usage = usage_from_json(usage)
      self.raw_usage = Some(usage)
    }
    _ => ()
  }
  let reason = match response {
    { "incomplete_details": { "reason": String(value), .. }, .. } => value
    _ => ""
  }
  if event_type == "response.failed" {
    self.finish_reason = @provider.Error
    self.finish_reason_raw = match response {
      { "error": { "code": String(value), .. }, .. } => Some(value)
      { "status": String(value), .. } => Some(value)
      _ => None
    }
    if self.emit_failed_error {
      let message = match response {
        { "error": { "message": String(value), .. }, .. } => value
        _ => "Open Responses request failed"
      }
      events.push(@provider.StreamError(message))
    }
  } else {
    self.finish_reason_raw = if reason == "" { None } else { Some(reason) }
    self.finish_reason = map_finish_reason(
      reason,
      self.tool_calls.length() > 0 || self.has_provider_extension_tool_calls(),
    )
  }
}

///|
fn OpenResponsesStreamDecoder::apply_json(
  self : OpenResponsesStreamDecoder,
  json : Json,
) -> (Array[@provider.StreamEvent], Bool) {
  let events : Array[@provider.StreamEvent] = []
  let mut done = false
  let event_type = @provider_utils.json_string_field(json, "type").unwrap_or("")
  match event_type {
    "response.created" =>
      match json {
        { "response": response, .. } => {
          let metadata = @provider.ResponseMetadata::from_json(response)
          if !metadata.is_empty() {
            events.push(@provider.ResponseMetadataReady(metadata))
          }
        }
        _ => ()
      }
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
            let _ = self.start_reasoning("\{id}:0", events)
          } else if kind == "function_call" {
            let index = self.update_tool_from_item(Json::object(item))
            if self.progressive_tool_calls {
              self.start_tool(index, events)
              self.emit_complete_tool_arguments_if_unseen(index, events)
            }
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
        let index = self.start_text(id, events)
        self.text_parts[index].write_string(delta)
        events.push(@provider.TextDelta(id~, delta~))
      }
    }
    "response.output_text.done" | "response.refusal.done" => {
      let id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "text-0",
      )
      self.finish_text(id, events)
    }
    "response.reasoning_text.delta" => {
      let id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "reasoning-0",
      )
      let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
      let id = self.reasoning_event_id(id)
      let _ = self.start_reasoning(id, events)
      if delta != "" {
        self.reasoning.write_string(delta)
        let index = self.start_reasoning(id, events)
        self.reasoning_parts[index].write_string(delta)
        events.push(@provider.ReasoningDelta(id~, delta~))
      }
    }
    "response.reasoning_summary_text.delta" => {
      let id = reasoning_summary_id(json)
      let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
      let _ = self.start_reasoning(id, events)
      if delta != "" {
        self.reasoning.write_string(delta)
        let index = self.start_reasoning(id, events)
        self.reasoning_parts[index].write_string(delta)
        events.push(@provider.ReasoningDelta(id~, delta~))
      }
    }
    "response.reasoning_text.done" => {
      let id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
        "reasoning-0",
      )
      let id = self.reasoning_event_id(id)
      self.finish_reasoning(id, events)
    }
    "response.reasoning_summary_text.done" => {
      let id = reasoning_summary_id(json)
      self.finish_reasoning(id, events)
    }
    "response.reasoning_summary_part.added" => {
      let id = reasoning_summary_id(json)
      let _ = self.start_reasoning(id, events)
    }
    "response.reasoning_summary_part.done" => {
      let id = reasoning_summary_id(json)
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
      let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
      if delta != "" {
        self.tool_arguments[index] = self.tool_arguments[index] + delta
      }
      if self.progressive_tool_calls && self.tool_names[index] != "" {
        let was_started = self.tool_started[index]
        self.start_tool(index, events)
        if was_started && delta != "" {
          self.tool_emitted_arguments[index] = self.tool_emitted_arguments[index] +
            delta
          events.push(
            @provider.ToolInputDelta(id=self.tool_stream_id(index), delta~),
          )
        } else if !was_started {
          self.emit_complete_tool_arguments_if_unseen(index, events)
        }
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
      if @provider_utils.json_string_field(json, "call_id") is Some(value) {
        self.tool_call_ids[index] = value
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
            let id = self.reasoning_event_id(id)
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
      self.finish_reason = @provider.Error
      self.finish_reason_raw = match json {
        { "error": { "code": String(value), .. }, .. } => Some(value)
        { "error": { "type": String(value), .. }, .. } => Some(value)
        _ => Some("error")
      }
      events.push(@provider.StreamError(message))
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
) -> Array[@provider.StreamEvent] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.StreamEvent] = []
  for index, id in self.text_ids {
    if !self.text_stopped[index] {
      self.text_stopped[index] = true
      events.push(@provider.TextEnd(id))
    }
  }
  for index, id in self.reasoning_ids {
    if !self.reasoning_stopped[index] {
      self.reasoning_stopped[index] = true
      events.push(@provider.ReasoningEnd(id))
    }
  }
  for index, _ in self.tool_item_ids {
    if self.progressive_tool_calls &&
      self.tool_started[index] &&
      !self.tool_ready[index] {
      events.push(@provider.ToolInputEnd(self.tool_stream_id(index)))
    }
  }
  events.push(@provider.Finish(usage=self.usage, reason=self.finish_reason))
  events
}

///|
fn OpenResponsesStreamDecoder::decode_data(
  self : OpenResponsesStreamDecoder,
  data : String,
) -> @provider_utils.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error =>
      return {
        events: [
          @provider.StreamError(
            "Open Responses stream decode error: \{error}; data: \{data}",
          ),
        ],
        consumed_event: true,
        done: false,
      }
  }
  self.record_json(json)
  (self.observe_json)(json)
  if self.validate_json is Some(validate) {
    validate(json)
  }
  let provider_events = (self.observe_events)(json)
  let (events, done) = self.apply_json(json)
  let combined_events : Array[@provider.StreamEvent] = []
  for event in provider_events {
    combined_events.push(event)
  }
  for event in events {
    combined_events.push(event)
  }
  if self.include_raw_chunks {
    let all_events : Array[@provider.StreamEvent] = [@provider.Raw(json)]
    for event in combined_events {
      all_events.push(event)
    }
    { events: all_events, consumed_event: true, done }
  } else {
    { events: combined_events, consumed_event: true, done }
  }
}

///|
/// Feed one physical SSE line.
pub fn OpenResponsesStreamDecoder::feed_line(
  self : OpenResponsesStreamDecoder,
  raw : String,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated SSE payload.
pub fn OpenResponsesStreamDecoder::flush_buffered(
  self : OpenResponsesStreamDecoder,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Return the accumulated normalized response.
pub fn OpenResponsesStreamDecoder::response(
  self : OpenResponsesStreamDecoder,
) -> @provider.ChatResponse {
  let provider_metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    (self.build_provider_metadata)(),
  )
  let normalized : Array[@provider.GeneratedContent] = []
  for item in self.content_order {
    match item {
      ResponsesText(index) => {
        let value = self.text_parts[index].to_string()
        if value != "" {
          normalized.push(@provider.GeneratedContent::text(value))
        }
      }
      ResponsesReasoning(index) => {
        let value = self.reasoning_parts[index].to_string()
        if value != "" {
          normalized.push(@provider.GeneratedContent::reasoning(value))
        }
      }
      ResponsesTool(index) =>
        if index < self.tool_calls.length() {
          normalized.push(
            @provider.GeneratedContent::tool_call(self.tool_calls[index]),
          )
        }
    }
  }
  let built = if self.use_built_content { (self.build_content)() } else { [] }
  let content = if built.length() > 0 { built } else { normalized }
  @provider.ChatResponse::from_content(content, self.usage, self.finish_reason).with_diagnostics(
    None,
    self.response_metadata,
    provider_metadata,
    [],
  )
}

///|
/// Return the accumulated V4 token usage, preserving provider-native fields.
pub fn OpenResponsesStreamDecoder::v4_usage(
  self : OpenResponsesStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  open_responses_v4_usage_from_json(self.raw_usage)
}

///|
/// Return the accumulated V4 finish reason and provider-native value.
pub fn OpenResponsesStreamDecoder::v4_finish_reason(
  self : OpenResponsesStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  @provider.LanguageModelV4FinishReason::from_finish_reason(self.finish_reason).with_raw(
    self.finish_reason_raw,
  )
}

///|
/// Return provider metadata collected from response chunks and extensions.
pub fn OpenResponsesStreamDecoder::provider_metadata_snapshot(
  self : OpenResponsesStreamDecoder,
) -> Map[String, Json] {
  @provider.merge_provider_metadata(
    self.provider_metadata,
    (self.build_provider_metadata)(),
  )
}

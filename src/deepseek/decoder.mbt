///|
/// Detail object returned by the DeepSeek API on failure.
pub(all) struct DeepSeekErrorDetail {
  message : String
  error_type : String?
  param : Json?
  code : Json?
} derive(Debug, Eq)

///|
/// Structured DeepSeek API error data.
pub(all) struct DeepSeekErrorData {
  error : DeepSeekErrorDetail
} derive(Debug, Eq)

///|
/// Decode a standard DeepSeek error response.
pub fn decode_deepseek_error_data(json : Json) -> DeepSeekErrorData? {
  match json {
    { "error": Object(fields) as detail, .. } =>
      match @provider_utils.json_string_field(detail, "message") {
        Some(message) =>
          Some({
            error: {
              message,
              error_type: @provider_utils.json_string_field(detail, "type"),
              param: fields.get("param"),
              code: fields.get("code"),
            },
          })
        None => None
      }
    _ => None
  }
}

///|
fn deepseek_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "message": String(message), "type": "error", .. } => Some(message)
    _ => None
  }
}

///|
/// Decode one complete DeepSeek Chat Completions response.
pub fn decode_deepseek_chat_response(
  json : Json,
  provider_name? : String = "deepseek.chat",
  id_generator? : @provider_utils.IdGenerator,
) -> @provider.ChatResponse raise {
  if deepseek_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="DeepSeek request failed: " + message,
      data=json,
    )
  }
  let choice = match json {
    { "choices": [value, ..], .. } => value
    { "choices": [], .. } =>
      raise @provider.InvalidResponseDataError(
        message="DeepSeek response has no choices",
        data=json,
      )
    _ =>
      raise @provider.InvalidResponseDataError(
        message="DeepSeek response has no valid choice",
        data=json,
      )
  }
  let message = match choice {
    { "message": Object(_) as value, .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="DeepSeek response choice has no message",
        data=json,
      )
  }
  let content : Array[@provider.GeneratedContent] = []
  let generate_id = id_generator.unwrap_or(@provider_utils.generate_id)
  match message {
    { "reasoning_content": String(value), .. } if value != "" =>
      content.push(@provider.GeneratedContent::reasoning(value))
    _ => ()
  }
  let mut has_tool_calls = false
  match message {
    { "tool_calls": Array(values), .. } =>
      for value in values {
        match value {
          {
            "id": String(id),
            "function": {
              "name": String(name),
              "arguments": String(arguments),
              ..
            },
            ..
          } => {
            content.push(
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(id~, name~, arguments~),
              ),
            )
            has_tool_calls = true
          }
          {
            "function": {
              "name": String(name),
              "arguments": String(arguments),
              ..
            },
            ..
          } => {
            content.push(
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(id=generate_id(), name~, arguments~),
              ),
            )
            has_tool_calls = true
          }
          _ => ()
        }
      }
    _ => ()
  }
  match message {
    { "content": String(value), .. } if value != "" =>
      content.push(@provider.GeneratedContent::text(value))
    _ => ()
  }
  let usage_json = match json {
    { "usage": value, .. } if !(value is Null) => value
    _ => Json::null()
  }
  let usage = if usage_json is Null {
    @provider.Usage::zero()
  } else {
    convert_deepseek_usage(usage_json)
  }
  let finish_reason = match choice {
    { "finish_reason": String(value), .. } => deepseek_finish_reason(value)
    _ => if has_tool_calls { @provider.ToolCalls } else { @provider.Stop }
  }
  let metadata = @provider.merge_provider_metadata(
    @provider_utils.provider_metadata_from_json(json, provider_name),
    if usage_json is Null {
      Map([])
    } else {
      deepseek_usage_metadata(usage_json, provider_name)
    },
  )
  @provider.ChatResponse::from_content(content, usage, finish_reason).with_diagnostics(
    None,
    Some(@provider.ResponseMetadata::from_json(json)),
    metadata,
    [],
  )
}

///|
/// Stateful decoder for DeepSeek's Chat Completions SSE protocol.
pub struct DeepSeekStreamDecoder {
  priv sse : @provider_utils.EventSourceBuffer
  priv include_raw_chunks : Bool
  priv provider_name : String
  priv text : StringBuilder
  priv reasoning : StringBuilder
  priv tools : @provider_utils.ToolCallDeltaAssembler
  priv tool_stream_ids : Array[String]
  priv mut usage : @provider.Usage
  priv mut usage_json : Json
  priv mut finish_reason : @provider.FinishReason
  priv mut finish_reason_raw : String?
  priv mut response_metadata : @provider.ResponseMetadata?
  priv mut provider_metadata : Map[String, Json]
  priv mut metadata_emitted : Bool
  priv mut text_active : Bool
  priv mut reasoning_active : Bool
  priv mut text_seen : Bool
  priv mut reasoning_seen : Bool
  priv mut finalized : Bool
}

///|
/// Create an empty DeepSeek stream decoder.
pub fn DeepSeekStreamDecoder::new(
  include_raw_chunks? : Bool = false,
  provider_name? : String = "deepseek.chat",
  id_generator? : @provider_utils.IdGenerator,
) -> DeepSeekStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    provider_name,
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    tools: @provider_utils.ToolCallDeltaAssembler::new(id_generator?),
    tool_stream_ids: [],
    usage: @provider.Usage::zero(),
    usage_json: Json::null(),
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    response_metadata: None,
    provider_metadata: Map([]),
    metadata_emitted: false,
    text_active: false,
    reasoning_active: false,
    text_seen: false,
    reasoning_seen: false,
    finalized: false,
  }
}

///|
fn DeepSeekStreamDecoder::record_metadata(
  self : DeepSeekStreamDecoder,
  json : Json,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let response = @provider.ResponseMetadata::from_json(json)
  if !response.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, response),
    )
  }
  if !self.metadata_emitted {
    self.metadata_emitted = true
    events.push(@provider.ResponseMetadataReady(response))
  }
  self.provider_metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    @provider_utils.provider_metadata_from_json(json, self.provider_name),
  )
}

///|
fn DeepSeekStreamDecoder::ensure_tool_stream_id(
  self : DeepSeekStreamDecoder,
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
fn DeepSeekStreamDecoder::close_reasoning(
  self : DeepSeekStreamDecoder,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if self.reasoning_active {
    self.reasoning_active = false
    events.push(@provider.ReasoningEnd("reasoning-0"))
  }
}

///|
fn DeepSeekStreamDecoder::close_text(
  self : DeepSeekStreamDecoder,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if self.text_active {
    self.text_active = false
    events.push(@provider.TextEnd("text-0"))
  }
}

///|
fn DeepSeekStreamDecoder::apply_tool_delta(
  self : DeepSeekStreamDecoder,
  value : Json,
  fallback_index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit raise {
  guard value is Object(_) else { return }
  let index = match value {
    { "index": Number(number, ..), .. } => number.to_int()
    _ => fallback_index
  }
  let id = match value {
    { "id": String(value), .. } => Some(value)
    _ => None
  }
  let name = match value {
    { "function": { "name": String(value), .. }, .. } => Some(value)
    _ => None
  }
  let arguments_delta = match value {
    { "function": { "arguments": String(value), .. }, .. } => Some(value)
    _ => None
  }
  let applied = self.tools.apply(
    @provider_utils.ToolCallDelta::new(index~, id?, name?, arguments_delta?),
  )
  self.ensure_tool_stream_id(index, applied.stream_id)
  if applied.started {
    events.push(
      @provider.ToolInputStart(
        id=applied.stream_id,
        tool_name=applied.tool_name,
      ),
    )
  }
  if applied.arguments_delta != "" {
    events.push(
      @provider.ToolInputDelta(
        id=applied.stream_id,
        delta=applied.arguments_delta,
      ),
    )
  }
}

///|
fn DeepSeekStreamDecoder::apply_json(
  self : DeepSeekStreamDecoder,
  json : Json,
) -> Array[@provider.StreamEvent] raise {
  let events : Array[@provider.StreamEvent] = []
  self.record_metadata(json, events)
  match json {
    { "usage": value, .. } if !(value is Null) => {
      self.usage_json = value
      self.usage = convert_deepseek_usage(value)
    }
    _ => ()
  }
  match json {
    { "choices": [{ "finish_reason": String(value), .. }, ..], .. } => {
      self.finish_reason_raw = Some(value)
      self.finish_reason = deepseek_finish_reason(value)
    }
    _ => ()
  }
  match json {
    { "choices": [{ "delta": Object(delta), .. }, ..], .. } => {
      match delta {
        { "reasoning_content": String(value), .. } if value != "" => {
          self.close_text(events)
          if !self.reasoning_active {
            self.reasoning_active = true
            self.reasoning_seen = true
            events.push(@provider.ReasoningStart("reasoning-0"))
          }
          self.reasoning.write_string(value)
          events.push(@provider.ReasoningDelta(id="reasoning-0", delta=value))
        }
        _ => ()
      }
      match delta {
        { "content": String(value), .. } if value != "" => {
          self.close_reasoning(events)
          if !self.text_active {
            self.text_active = true
            self.text_seen = true
            events.push(@provider.TextStart("text-0"))
          }
          self.text.write_string(value)
          events.push(@provider.TextDelta(id="text-0", delta=value))
        }
        _ => ()
      }
      match delta {
        { "tool_calls": Array(values), .. } => {
          self.close_reasoning(events)
          self.close_text(events)
          for index, value in values {
            self.apply_tool_delta(value, index, events)
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
  events
}

///|
fn DeepSeekStreamDecoder::finish_events(
  self : DeepSeekStreamDecoder,
) -> Array[@provider.StreamEvent] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.StreamEvent] = []
  self.close_reasoning(events)
  self.close_text(events)
  let calls = self.tools.calls()
  if !(self.finish_reason is @provider.Error) {
    for index, call in calls {
      let stream_id = if index < self.tool_stream_ids.length() &&
        self.tool_stream_ids[index] != "" {
        self.tool_stream_ids[index]
      } else {
        call.id
      }
      events.push(@provider.ToolInputEnd(stream_id))
      events.push(@provider.ToolCallReady(call))
    }
  }
  let reason = match self.finish_reason {
    @provider.Unknown("") =>
      if calls.length() > 0 {
        @provider.ToolCalls
      } else {
        @provider.Stop
      }
    value => value
  }
  self.finish_reason = reason
  events.push(@provider.Finish(usage=self.usage, reason~))
  events
}

///|
fn DeepSeekStreamDecoder::decode_data(
  self : DeepSeekStreamDecoder,
  data : String,
) -> @provider_utils.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.finish_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    _ =>
      raise @provider.InvalidResponseDataError(
        message="DeepSeek stream decode error",
        data=Json::string(data),
      )
  }
  if deepseek_error_message(json) is Some(message) {
    self.finish_reason = @provider.Error
    let events : Array[@provider.StreamEvent] = [@provider.StreamError(message)]
    for event in self.finish_events() {
      events.push(event)
    }
    if self.include_raw_chunks {
      events.insert(0, @provider.Raw(json))
    }
    return { events, consumed_event: true, done: true }
  }
  let events = self.apply_json(json)
  if self.include_raw_chunks {
    events.insert(0, @provider.Raw(json))
  }
  { events, consumed_event: true, done: false }
}

///|
/// Feed one physical SSE line into the DeepSeek decoder.
pub fn DeepSeekStreamDecoder::feed_line(
  self : DeepSeekStreamDecoder,
  raw : String,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated DeepSeek SSE payload.
pub fn DeepSeekStreamDecoder::flush_buffered(
  self : DeepSeekStreamDecoder,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.flush() {
    Some(data) => {
      let batch = self.decode_data(data)
      if batch.done {
        batch
      } else {
        let events = batch.events
        for event in self.finish_events() {
          events.push(event)
        }
        { events, consumed_event: batch.consumed_event, done: true }
      }
    }
    None =>
      if self.finalized {
        @provider_utils.DecodeBatch::empty(true)
      } else if !(self.finish_reason is @provider.Unknown("")) {
        { events: self.finish_events(), consumed_event: false, done: true }
      } else {
        @provider_utils.DecodeBatch::empty(false)
      }
  }
}

///|
/// Return the accumulated DeepSeek stream response.
pub fn DeepSeekStreamDecoder::response(
  self : DeepSeekStreamDecoder,
) -> @provider.ChatResponse {
  let content : Array[@provider.GeneratedContent] = []
  if self.reasoning_seen {
    content.push(
      @provider.GeneratedContent::reasoning(self.reasoning.to_string()),
    )
  }
  if !(self.finish_reason is @provider.Error) {
    for call in self.tools.calls() {
      content.push(@provider.GeneratedContent::tool_call(call))
    }
  }
  if self.text_seen {
    content.push(@provider.GeneratedContent::text(self.text.to_string()))
  }
  let metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    if self.usage_json is Null {
      Map([])
    } else {
      deepseek_usage_metadata(self.usage_json, self.provider_name)
    },
  )
  @provider.ChatResponse::from_content(content, self.usage, self.finish_reason).with_diagnostics(
    None,
    self.response_metadata,
    metadata,
    [],
  )
}

///|
fn deepseek_v4_usage_from_raw(
  raw_usage : Json?,
) -> @provider.LanguageModelV4Usage {
  match raw_usage {
    Some(raw) if !(raw is Null) =>
      @provider.LanguageModelV4Usage::from_usage(convert_deepseek_usage(raw)).with_raw(
        Some(raw),
      )
    _ => @provider.LanguageModelV4Usage::unknown()
  }
}

///|
fn deepseek_v4_finish_reason_from_raw(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  match raw {
    Some(value) =>
      @provider.LanguageModelV4FinishReason::from_finish_reason(
        deepseek_finish_reason(value),
      ).with_raw(Some(value))
    None => @provider.LanguageModelV4FinishReason::unknown()
  }
}

///|
/// Return lossless V4 usage accumulated from the terminal SSE chunk.
pub fn DeepSeekStreamDecoder::v4_usage(
  self : DeepSeekStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  deepseek_v4_usage_from_raw(
    if self.usage_json is Null {
      None
    } else {
      Some(self.usage_json)
    },
  )
}

///|
/// Return the normalized and provider-native finish reason.
pub fn DeepSeekStreamDecoder::v4_finish_reason(
  self : DeepSeekStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  deepseek_v4_finish_reason_from_raw(self.finish_reason_raw)
}

///|
/// Return a copy of provider metadata collected while decoding the stream.
pub fn DeepSeekStreamDecoder::provider_metadata_snapshot(
  self : DeepSeekStreamDecoder,
) -> Map[String, Json] {
  @provider.copy_provider_metadata(self.response().provider_metadata)
}

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
fn decode_deepseek_error_data(json : Json) -> DeepSeekErrorData? {
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
fn deepseek_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match decode_deepseek_error_data(json) {
    Some(data) => Some(data.error.message)
    None =>
      match json {
        { "message": String(message), "type": "error", .. } => Some(message)
        _ => None
      }
  }
}

///|
fn deepseek_finish_reason(value : String) -> @provider.FinishReason {
  match value {
    "stop" => @provider.Stop
    "length" => @provider.Length
    "content_filter" => @provider.ContentFilter
    "tool_calls" => @provider.ToolCalls
    "insufficient_system_resource" => @provider.Error
    other => @provider.Unknown(other)
  }
}

///|
priv struct DeepSeekDecodedResponse {
  content : Array[@provider.LanguageModelV4Content]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  provider_metadata : Map[String, Json]
  response : @provider.ResponseMetadata?
}

///|
/// Decode one complete DeepSeek Chat Completions response.
fn decode_deepseek_chat_response(
  json : Json,
  provider_name~ : String,
  id_generator~ : @provider_utils.IdGenerator,
) -> DeepSeekDecodedResponse raise {
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
  let content : Array[@provider.LanguageModelV4Content] = []
  let generate_id = id_generator
  match message {
    { "reasoning_content": String(value), .. } if value != "" =>
      content.push(@provider.LanguageModelV4Content::reasoning(value))
    _ => ()
  }
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
          } =>
            content.push(
              @provider.LanguageModelV4Content::tool_call({
                tool_call_id: id,
                tool_name: name,
                input: arguments,
                provider_executed: false,
                dynamic: false,
                provider_metadata: Map([]),
              }),
            )
          {
            "function": {
              "name": String(name),
              "arguments": String(arguments),
              ..
            },
            ..
          } =>
            content.push(
              @provider.LanguageModelV4Content::tool_call({
                tool_call_id: generate_id(),
                tool_name: name,
                input: arguments,
                provider_executed: false,
                dynamic: false,
                provider_metadata: Map([]),
              }),
            )
          _ => ()
        }
      }
    _ => ()
  }
  match message {
    { "content": String(value), .. } if value != "" =>
      content.push(@provider.LanguageModelV4Content::text(value))
    _ => ()
  }
  let usage_json = match json {
    { "usage": value, .. } if !(value is Null) => value
    _ => Json::null()
  }
  let usage = convert_deepseek_usage(
    if usage_json is Null {
      None
    } else {
      Some(usage_json)
    },
  )
  let finish_reason = deepseek_v4_finish_reason_from_raw(
    match choice {
      { "finish_reason": String(value), .. } => Some(value)
      _ => None
    },
  )
  let metadata = @provider.merge_provider_metadata(
    @provider_utils.provider_metadata_from_json(json, provider_name),
    deepseek_usage_metadata(
      if usage_json is Null {
        Json::empty_object()
      } else {
        usage_json
      },
      provider_name,
    ),
  )
  {
    content,
    usage,
    finish_reason,
    provider_metadata: metadata,
    response: Some(
      @provider_utils.create_language_model_response_metadata(
        id?=@provider_utils.json_string_field(json, "id"),
        model?=@provider_utils.json_string_field(json, "model"),
        created?=@provider_utils.json_int_field_opt(json, "created"),
      ),
    ),
  }
}

///|
/// Stateful decoder for DeepSeek's Chat Completions SSE protocol.
priv struct DeepSeekStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  provider_name : String
  tools : @provider_utils.StreamingToolCallTracker
  mut usage_json : Json
  mut finish_reason : @provider.FinishReason
  mut finish_reason_raw : String?
  mut response_metadata : @provider.ResponseMetadata?
  mut provider_metadata : Map[String, Json]
  mut metadata_emitted : Bool
  mut text_active : Bool
  mut reasoning_active : Bool
  mut finalized : Bool
}

///|
/// Create an empty DeepSeek stream decoder.
fn DeepSeekStreamDecoder::new(
  include_raw_chunks~ : Bool,
  provider_name~ : String,
  id_generator~ : @provider_utils.IdGenerator,
) -> DeepSeekStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    provider_name,
    tools: @provider_utils.StreamingToolCallTracker::new(id_generator~),
    usage_json: Json::null(),
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    response_metadata: None,
    provider_metadata: Map([]),
    metadata_emitted: false,
    text_active: false,
    reasoning_active: false,
    finalized: false,
  }
}

///|
fn DeepSeekStreamDecoder::record_metadata(
  self : DeepSeekStreamDecoder,
  json : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  let response = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created"),
  )
  if !response.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, response),
    )
  }
  if !self.metadata_emitted {
    self.metadata_emitted = true
    events.push(@provider.V4ResponseMetadataReady(response))
  }
  self.provider_metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    @provider_utils.provider_metadata_from_json(json, self.provider_name),
  )
}

///|
fn DeepSeekStreamDecoder::close_reasoning(
  self : DeepSeekStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.reasoning_active {
    self.reasoning_active = false
    events.push(
      @provider.V4ReasoningEnd(id="reasoning-0", provider_metadata=Map([])),
    )
  }
}

///|
fn DeepSeekStreamDecoder::close_text(
  self : DeepSeekStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.text_active {
    self.text_active = false
    events.push(@provider.V4TextEnd(id="txt-0", provider_metadata=Map([])))
  }
}

///|
fn DeepSeekStreamDecoder::apply_tool_delta(
  self : DeepSeekStreamDecoder,
  value : Json,
  fallback_index : Int,
  events : Array[@provider.LanguageModelV4StreamPart],
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
  let tool_type = match value {
    { "type": String(value), .. } => Some(value)
    _ => None
  }
  for
    event in self.tools.process_delta_v4(
      @provider_utils.StreamingToolCallDelta::new(
        index~,
        id?,
        tool_type?,
        function_name?=name,
        arguments_delta?,
        data=value,
      ),
    ) {
    events.push(event)
  }
}

///|
fn DeepSeekStreamDecoder::apply_json(
  self : DeepSeekStreamDecoder,
  json : Json,
) -> Array[@provider.LanguageModelV4StreamPart] raise {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.record_metadata(json, events)
  match json {
    { "usage": value, .. } if !(value is Null) => self.usage_json = value
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
          if !self.reasoning_active {
            self.reasoning_active = true
            events.push(
              @provider.V4ReasoningStart(
                id="reasoning-0",
                provider_metadata=Map([]),
              ),
            )
          }
          events.push(
            @provider.V4ReasoningDelta(
              id="reasoning-0",
              delta=value,
              provider_metadata=Map([]),
            ),
          )
        }
        _ => ()
      }
      match delta {
        { "content": String(value), .. } if value != "" => {
          if !self.text_active {
            self.text_active = true
            events.push(
              @provider.V4TextStart(id="txt-0", provider_metadata=Map([])),
            )
          }
          self.close_reasoning(events)
          events.push(
            @provider.V4TextDelta(
              id="txt-0",
              delta=value,
              provider_metadata=Map([]),
            ),
          )
        }
        _ => ()
      }
      match delta {
        { "tool_calls": Array(values), .. } => {
          self.close_reasoning(events)
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
fn deepseek_optional_string_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(String(_)) => true
    _ => false
  }
}

///|
fn deepseek_optional_number_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(Number(_)) => true
    _ => false
  }
}

///|
fn deepseek_usage_validation_error(value : Json) -> String? {
  match value {
    Null => None
    Object(fields) => {
      for
        name in [
          "prompt_tokens", "completion_tokens", "prompt_cache_hit_tokens", "prompt_cache_miss_tokens",
          "total_tokens",
        ] {
        if !deepseek_optional_number_field_is_valid(fields, name) {
          return Some("DeepSeek usage.\{name} must be a number or null")
        }
      }
      match fields.get("completion_tokens_details") {
        None | Some(Null) => None
        Some(Object(details)) =>
          if deepseek_optional_number_field_is_valid(
              details, "reasoning_tokens",
            ) {
            None
          } else {
            Some(
              "DeepSeek usage.completion_tokens_details.reasoning_tokens must be a number or null",
            )
          }
        _ =>
          Some(
            "DeepSeek usage.completion_tokens_details must be an object or null",
          )
      }
    }
    _ => Some("DeepSeek usage must be an object or null")
  }
}

///|
fn deepseek_tool_delta_validation_error(value : Json) -> String? {
  match value {
    Object(fields) => {
      guard fields.get("index") is Some(Number(_)) else {
        return Some("DeepSeek tool call delta must contain a numeric index")
      }
      guard deepseek_optional_string_field_is_valid(fields, "id") else {
        return Some("DeepSeek tool call delta id must be a string or null")
      }
      match fields.get("function") {
        Some(Object(function)) => {
          if !deepseek_optional_string_field_is_valid(function, "name") {
            return Some(
              "DeepSeek tool call delta function.name must be a string or null",
            )
          }
          if !deepseek_optional_string_field_is_valid(function, "arguments") {
            return Some(
              "DeepSeek tool call delta function.arguments must be a string or null",
            )
          }
          None
        }
        _ => Some("DeepSeek tool call delta must contain a function object")
      }
    }
    _ => Some("DeepSeek tool call delta must be an object")
  }
}

///|
fn deepseek_delta_validation_error(value : Json) -> String? {
  match value {
    Null => None
    Object(fields) => {
      match fields.get("role") {
        None | Some(Null) | Some(String("assistant")) => ()
        _ => return Some("DeepSeek delta role must be assistant or null")
      }
      for name in ["content", "reasoning_content"] {
        if !deepseek_optional_string_field_is_valid(fields, name) {
          return Some("DeepSeek delta \{name} must be a string or null")
        }
      }
      match fields.get("tool_calls") {
        None | Some(Null) => None
        Some(Array(values)) => {
          for tool_call in values {
            if deepseek_tool_delta_validation_error(tool_call) is Some(error) {
              return Some(error)
            }
          }
          None
        }
        _ => Some("DeepSeek delta tool_calls must be an array or null")
      }
    }
    _ => Some("DeepSeek delta must be an object or null")
  }
}

///|
fn deepseek_stream_chunk_validation_error(json : Json) -> String? {
  match json {
    Object(fields) => {
      if !deepseek_optional_string_field_is_valid(fields, "id") ||
        !deepseek_optional_string_field_is_valid(fields, "model") {
        return Some("DeepSeek stream id and model must be strings or null")
      }
      if !deepseek_optional_number_field_is_valid(fields, "created") {
        return Some("DeepSeek stream created must be a number or null")
      }
      let choices = match fields.get("choices") {
        Some(Array(values)) => values
        _ => return Some("DeepSeek stream chunk must contain a choices array")
      }
      for choice in choices {
        match choice {
          Object(choice_fields) => {
            if !deepseek_optional_string_field_is_valid(
                choice_fields, "finish_reason",
              ) {
              return Some(
                "DeepSeek stream finish_reason must be a string or null",
              )
            }
            match choice_fields.get("delta") {
              None => ()
              Some(delta) =>
                if deepseek_delta_validation_error(delta) is Some(error) {
                  return Some(error)
                }
            }
          }
          _ => return Some("DeepSeek stream choice must be an object")
        }
      }
      match fields.get("usage") {
        Some(usage) => deepseek_usage_validation_error(usage)
        None => None
      }
    }
    _ => Some("DeepSeek stream chunk must be a JSON object")
  }
}

///|
fn DeepSeekStreamDecoder::invalid_stream_chunk(
  self : DeepSeekStreamDecoder,
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
fn DeepSeekStreamDecoder::finish_events(
  self : DeepSeekStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.close_reasoning(events)
  self.close_text(events)
  for event in self.tools.flush_v4() {
    events.push(event)
  }
  events.push(
    @provider.V4Finish(
      usage=self.v4_usage(),
      reason=self.v4_finish_reason(),
      provider_metadata=self.provider_metadata_snapshot(),
    ),
  )
  events
}

///|
fn DeepSeekStreamDecoder::decode_data(
  self : DeepSeekStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  if data.trim() == "[DONE]" {
    return { events: self.finish_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => {
      self.finish_reason = @provider.Error
      self.finish_reason_raw = None
      let events : Array[@provider.LanguageModelV4StreamPart] = [
        @provider.V4Error(
          @provider.StreamErrorInfo::new(
            "DeepSeek stream decode error: \{error}; data: \{data}",
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
  if deepseek_error_message(json) is Some(message) {
    self.finish_reason = @provider.Error
    self.finish_reason_raw = None
    let error_data = match json {
      { "error": value, .. } => value
      _ => json
    }
    let events : Array[@provider.LanguageModelV4StreamPart] = [
      @provider.V4Error(
        @provider.StreamErrorInfo::new(message, data=error_data),
      ),
    ]
    if self.include_raw_chunks {
      events.insert(0, @provider.V4Raw(json))
    }
    return { events, consumed_event: true, done: false }
  }
  if deepseek_stream_chunk_validation_error(json) is Some(message) {
    return self.invalid_stream_chunk(message, json)
  }
  let events = self.apply_json(json)
  if self.include_raw_chunks {
    events.insert(0, @provider.V4Raw(json))
  }
  { events, consumed_event: true, done: false }
}

///|
/// Feed one physical SSE line into the DeepSeek decoder.
fn DeepSeekStreamDecoder::feed_line(
  self : DeepSeekStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated DeepSeek SSE payload.
fn DeepSeekStreamDecoder::flush_buffered(
  self : DeepSeekStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Finish the protocol transform after the transport reports a normal EOF.
fn DeepSeekStreamDecoder::finish_stream(
  self : DeepSeekStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    @provider_utils.SseDecodeBatch::empty(true)
  } else {
    { events: self.finish_events(), consumed_event: false, done: true }
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
fn DeepSeekStreamDecoder::v4_usage(
  self : DeepSeekStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  convert_deepseek_usage(
    if self.usage_json is Null {
      None
    } else {
      Some(self.usage_json)
    },
  )
}

///|
/// Return the normalized and provider-native finish reason.
fn DeepSeekStreamDecoder::v4_finish_reason(
  self : DeepSeekStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  match self.finish_reason_raw {
    Some(value) => deepseek_v4_finish_reason_from_raw(Some(value))
    None =>
      if self.finish_reason is @provider.Error {
        @provider.LanguageModelV4FinishReason::from_finish_reason(
          @provider.Error,
        )
      } else {
        @provider.LanguageModelV4FinishReason::unknown()
      }
  }
}

///|
/// Return a copy of provider metadata collected while decoding the stream.
fn DeepSeekStreamDecoder::provider_metadata_snapshot(
  self : DeepSeekStreamDecoder,
) -> Map[String, Json] {
  @provider.merge_provider_metadata(
    self.provider_metadata,
    deepseek_usage_metadata(
      if self.usage_json is Null {
        Json::empty_object()
      } else {
        self.usage_json
      },
      self.provider_name,
    ),
  )
}

///|
fn DeepSeekStreamDecoder::response_metadata_snapshot(
  self : DeepSeekStreamDecoder,
) -> @provider.ResponseMetadata? {
  self.response_metadata
}

///|
/// Detail object returned by the Moonshot AI API on failure.
pub(all) struct MoonshotErrorDetail {
  message : String
  error_type : String?
  code : String?
} derive(Debug, Eq)

///|
/// Structured Moonshot AI API error data.
pub(all) struct MoonshotErrorData {
  error : MoonshotErrorDetail
} derive(Debug, Eq)

///|
/// Decode a standard Moonshot AI error response.
fn decode_moonshot_error_data(json : Json) -> MoonshotErrorData? {
  match json {
    { "error": Object(fields) as detail, .. } =>
      match @provider_utils.json_string_field(detail, "message") {
        Some(message) =>
          Some({
            error: {
              message,
              error_type: @provider_utils.json_string_field(detail, "type"),
              code: match fields.get("code") {
                Some(String(value)) => Some(value)
                _ => None
              },
            },
          })
        None => None
      }
    _ => None
  }
}

///|
fn moonshot_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match decode_moonshot_error_data(json) {
    Some(data) => Some(data.error.message)
    None => None
  }
}

///|
/// Classify an in-band Moonshot stream error into transport metadata so the
/// retry policy can act on it (rate limits and server faults are retryable).
fn moonshot_stream_error_metadata(error_type : String?) -> (Int?, Bool?) {
  match error_type {
    Some("rate_limit_exceeded") | Some("rate_limit_error") =>
      (Some(429), Some(true))
    Some("server_error") | Some("api_error") | Some("internal_server_error") =>
      (Some(500), Some(true))
    Some("overloaded_error") | Some("service_unavailable") =>
      (Some(503), Some(true))
    Some("timeout") | Some("timeout_error") => (Some(504), Some(true))
    Some("authentication_error") | Some("invalid_api_key") =>
      (Some(401), Some(false))
    Some("permission_error") => (Some(403), Some(false))
    Some("not_found_error") | Some("model_not_found") =>
      (Some(404), Some(false))
    Some("bad_request")
    | Some("context_length_exceeded")
    | Some("invalid_request_error") => (Some(400), Some(false))
    _ => (None, None)
  }
}

///|
/// Map a raw Moonshot finish reason onto the unified set.
fn moonshot_finish_reason(value : String) -> @provider.FinishReason {
  match value {
    "stop" => @provider.Stop
    "length" => @provider.Length
    "content_filter" => @provider.ContentFilter
    "function_call" | "tool_calls" => @provider.ToolCalls
    other => @provider.Unknown(other)
  }
}

///|
fn moonshot_v4_finish_reason_from_raw(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  match raw {
    Some(value) =>
      @provider.LanguageModelV4FinishReason::from_finish_reason(
        moonshot_finish_reason(value),
      ).with_raw(Some(value))
    None => @provider.LanguageModelV4FinishReason::unknown()
  }
}

///|
priv struct MoonshotDecodedResponse {
  content : Array[@provider.LanguageModelV4Content]
  usage : @provider.LanguageModelV4Usage
  finish_reason : @provider.LanguageModelV4FinishReason
  provider_metadata : Map[String, Json]
  response : @provider.ResponseMetadata?
}

///|
/// Decode one complete Moonshot AI Chat Completions response.
fn decode_moonshot_chat_response(
  json : Json,
  provider_name~ : String,
  id_generator~ : @provider_utils.IdGenerator,
) -> MoonshotDecodedResponse raise {
  if moonshot_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="Moonshot AI request failed: \{message}",
      data=json,
    )
  }
  let choice = match json {
    { "choices": [value, ..], .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Moonshot AI response has no valid choice",
        data=json,
      )
  }
  let message = match choice {
    { "message": Object(_) as value, .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Moonshot AI response choice has no message",
        data=json,
      )
  }
  let content : Array[@provider.LanguageModelV4Content] = []
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
            "function": {
              "name": String(name),
              "arguments": String(arguments),
              ..
            },
            ..
          } => {
            let id = match value {
              { "id": String(value), .. } => value
              _ => ""
            }
            content.push(
              @provider.LanguageModelV4Content::tool_call({
                // An empty id is treated as absent and replaced with a
                // generated one so downstream tool results stay resolvable.
                tool_call_id: if id == "" {
                  id_generator()
                } else {
                  id
                },
                tool_name: name,
                input: arguments,
                provider_executed: false,
                dynamic: false,
                provider_metadata: Map([]),
              }),
            )
          }
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
  let usage = convert_moonshotai_chat_usage(
    if usage_json is Null {
      None
    } else {
      Some(usage_json)
    },
  )
  let finish_reason = moonshot_v4_finish_reason_from_raw(
    match choice {
      { "finish_reason": String(value), .. } => Some(value)
      _ => None
    },
  )
  let metadata : Map[String, Json] = Map([])
  let details : Map[String, Json] = Map([])
  match choice {
    { "logprobs": value, .. } if !(value is Null) => details["logprobs"] = value
    _ => ()
  }
  match json {
    { "object": String(value), .. } =>
      details["responseObject"] = Json::string(value)
    _ => ()
  }
  match choice {
    { "index": Number(value, ..), .. } =>
      details["choiceIndex"] = Json::number(value)
    _ => ()
  }
  match message {
    { "role": String(value), .. } =>
      details["messageRole"] = Json::string(value)
    _ => ()
  }
  if details.length() > 0 {
    metadata[provider_name] = Json::object(details)
  }
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
/// Stateful decoder for Moonshot AI's Chat Completions SSE protocol.
priv struct MoonshotStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  provider_name : String
  tools : @provider_utils.StreamingToolCallTracker
  mut usage_json : Json
  mut choice_usage_json : Json
  mut finish_reason : @provider.FinishReason
  mut finish_reason_raw : String?
  mut response_metadata : @provider.ResponseMetadata?
  mut metadata_emitted : Bool
  mut text_active : Bool
  mut reasoning_active : Bool
  mut finalized : Bool
  logprobs_content : Array[Json]
  mut response_object : String?
  mut choice_index : Int?
  mut message_role : String?
  tool_call_types : Map[Int, String]
}

///|
/// Create an empty Moonshot stream decoder.
fn MoonshotStreamDecoder::new(
  include_raw_chunks~ : Bool,
  provider_name~ : String,
  id_generator~ : @provider_utils.IdGenerator,
) -> MoonshotStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    provider_name,
    tools: @provider_utils.StreamingToolCallTracker::new(id_generator~),
    usage_json: Json::null(),
    choice_usage_json: Json::null(),
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    response_metadata: None,
    metadata_emitted: false,
    text_active: false,
    reasoning_active: false,
    finalized: false,
    logprobs_content: [],
    response_object: None,
    choice_index: None,
    message_role: None,
    tool_call_types: Map([]),
  }
}

///|
fn MoonshotStreamDecoder::record_metadata(
  self : MoonshotStreamDecoder,
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
  match json {
    { "object": String(value), .. } => self.response_object = Some(value)
    _ => ()
  }
}

///|
fn MoonshotStreamDecoder::close_reasoning(
  self : MoonshotStreamDecoder,
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
fn MoonshotStreamDecoder::close_text(
  self : MoonshotStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.text_active {
    self.text_active = false
    events.push(@provider.V4TextEnd(id="txt-0", provider_metadata=Map([])))
  }
}

///|
fn MoonshotStreamDecoder::apply_tool_delta(
  self : MoonshotStreamDecoder,
  value : Json,
  fallback_index : Int,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit raise {
  guard value is Object(_) else { return }
  // Moonshot may omit the delta index; the position inside the delta
  // array is the fallback (AI SDK indexless tool-call fixtures).
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
  if tool_type is Some(tool_type_value) {
    self.tool_call_types[index] = tool_type_value
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
fn MoonshotStreamDecoder::apply_json(
  self : MoonshotStreamDecoder,
  json : Json,
) -> Array[@provider.LanguageModelV4StreamPart] raise {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.record_metadata(json, events)
  match json {
    { "usage": value, .. } if !(value is Null) => self.usage_json = value
    _ => ()
  }
  match json {
    { "choices": [choice, ..], .. } => {
      match choice {
        { "usage": Object(_), .. } =>
          self.choice_usage_json = match choice {
            { "usage": value, .. } => value
            _ => Json::null()
          }
        _ => ()
      }
      match choice {
        { "index": Number(value, ..), .. } =>
          self.choice_index = Some(value.to_int())
        _ => ()
      }
      match choice {
        { "finish_reason": String(value), .. } => {
          self.finish_reason_raw = Some(value)
          self.finish_reason = moonshot_finish_reason(value)
        }
        _ => ()
      }
      match choice {
        { "logprobs": { "content": Array(items), .. }, .. } =>
          for item in items {
            self.logprobs_content.push(item)
          }
        _ => ()
      }
    }
    _ => ()
  }
  match json {
    { "choices": [{ "delta": Object(delta), .. }, ..], .. } => {
      match delta {
        { "role": String(value), .. } => self.message_role = Some(value)
        _ => ()
      }
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
        // Empty tool-call arrays must not close an active reasoning block.
        { "tool_calls": Array(values), .. } if values.length() > 0 => {
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
fn MoonshotStreamDecoder::stream_error_events(
  self : MoonshotStreamDecoder,
  data : MoonshotErrorData,
  raw : Json,
) -> Array[@provider.LanguageModelV4StreamPart] {
  self.finish_reason = @provider.Error
  self.finish_reason_raw = None
  let (status_code, is_retryable) = moonshot_stream_error_metadata(
    data.error.error_type,
  )
  // The transport classification rides on the error payload so consumers
  // can drive retry decisions from a single value.
  let error_fields : Map[String, Json] = Map([
    ("message", Json::string(data.error.message)),
    (
      "type",
      match data.error.error_type {
        Some(value) => Json::string(value)
        None => Json::null()
      },
    ),
    (
      "code",
      match data.error.code {
        Some(value) => Json::string(value)
        None => Json::null()
      },
    ),
  ])
  match status_code {
    Some(value) => error_fields["statusCode"] = Json::number(value.to_double())
    None => ()
  }
  match is_retryable {
    Some(value) => error_fields["isRetryable"] = Json::boolean(value)
    None => ()
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = [
    @provider.V4Error(
      @provider.StreamErrorInfo::new(
        data.error.message,
        data=Json::object(Map([("error", Json::object(error_fields))])),
      ),
    ),
  ]
  if self.include_raw_chunks {
    events.insert(0, @provider.V4Raw(raw))
  }
  events
}

///|
fn MoonshotStreamDecoder::finish_events(
  self : MoonshotStreamDecoder,
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
  // Moonshot reports usage at the stream top level; some deployments move
  // it onto the choice. Top level wins.
  let usage_json = if !(self.usage_json is Null) {
    self.usage_json
  } else {
    self.choice_usage_json
  }
  let details : Map[String, Json] = Map([])
  if self.logprobs_content.length() > 0 {
    details["logprobs"] = {
      "content": Json::array(self.logprobs_content.copy()),
    }
  }
  match self.response_object {
    Some(value) => details["responseObject"] = Json::string(value)
    None => ()
  }
  match self.choice_index {
    Some(value) => details["choiceIndex"] = Json::number(value.to_double())
    None => ()
  }
  match self.message_role {
    Some(value) => details["messageRole"] = Json::string(value)
    None => ()
  }
  if self.tool_call_types.length() > 0 {
    let indices : Array[Int] = self.tool_call_types.keys().collect()
    indices.sort_by(fn(left, right) { left.compare(right) })
    let types : Array[Json] = []
    for index in indices {
      match self.tool_call_types.get(index) {
        Some(value) => types.push(Json::string(value))
        None => ()
      }
    }
    details["toolCallTypes"] = Json::array(types)
  }
  let metadata : Map[String, Json] = if details.length() > 0 {
    Map([(self.provider_name, Json::object(details))])
  } else {
    Map([])
  }
  let reason = match self.finish_reason_raw {
    Some(value) => moonshot_v4_finish_reason_from_raw(Some(value))
    None =>
      // A failed parse or in-band error leaves no raw reason; surface the
      // error state instead of a generic unknown.
      @provider.LanguageModelV4FinishReason::from_finish_reason(
        self.finish_reason,
      )
  }
  events.push(
    @provider.V4Finish(
      usage=convert_moonshotai_chat_usage(
        if usage_json is Null {
          None
        } else {
          Some(usage_json)
        },
      ),
      reason~,
      provider_metadata=metadata,
    ),
  )
  events
}

///|
fn MoonshotStreamDecoder::decode_data(
  self : MoonshotStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  if data.trim() == "[DONE]" {
    return { events: self.finish_events(), consumed_event: true, done: true, }
  }
  let json = @json.parse(data) catch {
    error => {
      self.finish_reason = @provider.Error
      self.finish_reason_raw = None
      let events : Array[@provider.LanguageModelV4StreamPart] = [
        @provider.V4Error(
          @provider.StreamErrorInfo::new(
            "Moonshot AI stream decode error: \{error}; data: \{data}",
            data=Json::string(data),
          ),
        ),
      ]
      if self.include_raw_chunks {
        events.insert(0, @provider.V4Raw(Json::string(data)))
      }
      return { events, consumed_event: true, done: false, }
    }
  }
  if decode_moonshot_error_data(json) is Some(error) {
    let raw = json
    return {
      events: self.stream_error_events(error, raw),
      consumed_event: true,
      done: false,
    }
  }
  let events = self.apply_json(json)
  if self.include_raw_chunks {
    events.insert(0, @provider.V4Raw(json))
  }
  { events, consumed_event: true, done: false, }
}

///|
/// Feed one physical SSE line into the Moonshot AI decoder.
fn MoonshotStreamDecoder::feed_line(
  self : MoonshotStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated Moonshot AI SSE payload.
fn MoonshotStreamDecoder::flush_buffered(
  self : MoonshotStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Finish the protocol transform after the transport reports a normal EOF.
fn MoonshotStreamDecoder::finish_stream(
  self : MoonshotStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    @provider_utils.SseDecodeBatch::empty(true)
  } else {
    { events: self.finish_events(), consumed_event: false, done: true, }
  }
}

///|
fn MoonshotStreamDecoder::response_metadata_snapshot(
  self : MoonshotStreamDecoder,
) -> @provider.ResponseMetadata? {
  self.response_metadata
}

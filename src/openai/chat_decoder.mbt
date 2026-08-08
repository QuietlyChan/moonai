///|
fn openai_chat_v4_usage(raw_usage : Json?) -> @provider.LanguageModelV4Usage {
  match raw_usage {
    Some(json) if !(json is Null) => {
      let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
      let output_tokens = @provider_utils.json_int_field(
        json, "completion_tokens",
      )
      let cached_input_tokens = match json {
        {
          "prompt_tokens_details": { "cached_tokens": Number(value, ..), .. },
          ..
        } => value.to_int()
        _ => 0
      }
      let cache_write_input_tokens = match json {
        {
          "prompt_tokens_details": {
            "cache_write_tokens": Number(value, ..),
            ..
          },
          ..
        } => Some(value.to_int())
        _ => None
      }
      let reasoning_tokens = match json {
        {
          "completion_tokens_details": {
            "reasoning_tokens": Number(value, ..),
            ..
          },
          ..
        } => value.to_int()
        _ => 0
      }
      {
        input_tokens: {
          total: Some(input_tokens),
          no_cache: Some(
            input_tokens -
            cached_input_tokens -
            cache_write_input_tokens.unwrap_or(0),
          ),
          cache_read: Some(cached_input_tokens),
          cache_write: cache_write_input_tokens,
        },
        output_tokens: {
          total: Some(output_tokens),
          text: Some(output_tokens - reasoning_tokens),
          reasoning: Some(reasoning_tokens),
        },
        raw: Some(json),
      }
    }
    _ => @provider_utils.create_null_language_model_usage()
  }
}

///|
fn openai_chat_finish_reason(value : String) -> @provider.FinishReason {
  match value {
    "stop" => @provider.Stop
    "length" => @provider.Length
    "content_filter" => @provider.ContentFilter
    "function_call" | "tool_calls" => @provider.ToolCalls
    "error" => @provider.Error
    other => @provider.Unknown(other)
  }
}

///|
fn openai_chat_v4_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("stop") => @provider.V4FinishStop
    Some("length") => @provider.V4FinishLength
    Some("content_filter") => @provider.V4FinishContentFilter
    Some("function_call") | Some("tool_calls") => @provider.V4FinishToolCalls
    _ => @provider.V4FinishOther
  }
  { unified, raw }
}

///|
/// Azure content-filter prelude chunks use `created: 0`; matching AI SDK, that
/// placeholder is not considered response metadata.
fn openai_chat_response_metadata(json : Json) -> @provider.ResponseMetadata {
  let created = match @provider_utils.json_int_field_opt(json, "created") {
    Some(0) => None
    other => other
  }
  @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?,
  )
}

///|
fn openai_chat_annotation_content(
  annotation : Json,
  source_id : String,
) -> @provider.LanguageModelV4Content? {
  match annotation {
    {
      "type": "url_citation",
      "url_citation": { "url": String(url), "title": String(title), .. },
      ..
    } =>
      Some(
        @provider.LanguageModelV4Content::url_source(id=source_id, url~, title~),
      )
    { "type": "url_citation", "url_citation": { "url": String(url), .. }, .. } =>
      Some(@provider.LanguageModelV4Content::url_source(id=source_id, url~))
    _ => None
  }
}

///|
fn append_openai_chat_annotations(
  content : Array[@provider.LanguageModelV4Content],
  annotations : Array[Json],
  id_generator : @provider_utils.IdGenerator,
) -> Unit {
  for index, annotation in annotations {
    let generated = id_generator()
    let source_id = if generated == "" { "source-\{index}" } else { generated }
    if openai_chat_annotation_content(annotation, source_id) is Some(source) {
      content.push(source)
    }
  }
}

///|
priv struct OpenAIChatDecodedResponse {
  content : Array[@provider.LanguageModelV4Content]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  provider_metadata : Map[String, Json]
  response : @provider.ResponseMetadata?
}

///|
/// Decode one non-streaming response using the official OpenAI response
/// contract. This intentionally does not depend on the compatible provider.
fn decode_openai_chat_response(
  json : Json,
  provider_name : String,
  id_generator : @provider_utils.IdGenerator,
) -> OpenAIChatDecodedResponse raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI Chat request failed: \{message}",
      data=json,
    )
  }
  let choice = match json {
    { "choices": [choice, ..], .. } => choice
    { "choices": [], .. } =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Chat response has no choices",
        data=json,
      )
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Chat response has no valid choice",
        data=json,
      )
  }
  let message = match choice {
    { "message": Object(_) as value, .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Chat response choice has no message",
        data=json,
      )
  }
  let content : Array[@provider.LanguageModelV4Content] = []
  let generate_id = id_generator
  match message {
    { "content": String(value), .. } if value != "" =>
      content.push(@provider.LanguageModelV4Content::text(value))
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
    { "annotations": Array(values), .. } =>
      append_openai_chat_annotations(content, values, generate_id)
    _ => ()
  }
  let raw_usage = match json {
    { "usage": value, .. } if !(value is Null) => Some(value)
    _ => None
  }
  let raw_finish_reason = match choice {
    { "finish_reason": String(value), .. } => Some(value)
    _ => None
  }
  let response_metadata = openai_chat_response_metadata(json)
  let provider_metadata = @provider.merge_provider_metadata(
    @provider_utils.provider_metadata_from_json(json, provider_name),
    openai_chat_metadata(json, provider_name),
  )
  {
    content,
    finish_reason: openai_chat_v4_finish_reason(raw_finish_reason),
    usage: openai_chat_v4_usage(raw_usage),
    provider_metadata,
    response: if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
  }
}

///|
/// Stateful SSE decoder owned by the official OpenAI Chat Completions model.
priv struct OpenAIChatStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  provider_name : String
  generate_id : @provider_utils.IdGenerator
  text : StringBuilder
  tools : @provider_utils.StreamingToolCallTracker
  metadata_fields : Map[String, Json]
  mut provider_metadata : Map[String, Json]
  mut raw_usage : Json?
  mut finish_reason : @provider.FinishReason
  mut finish_reason_raw : String?
  mut response_metadata : @provider.ResponseMetadata?
  mut source_index : Int
  mut text_started : Bool
  mut metadata_emitted : Bool
  mut output_started : Bool
  mut stream_started : Bool
  mut finalized : Bool
}

///|
fn OpenAIChatStreamDecoder::new(
  include_raw_chunks~ : Bool,
  provider_name~ : String,
  id_generator~ : @provider_utils.IdGenerator,
) -> OpenAIChatStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    provider_name,
    generate_id: id_generator,
    text: StringBuilder::new(),
    tools: @provider_utils.StreamingToolCallTracker::new(
      id_generator~,
      type_validation=@provider_utils.ValidateToolCallTypeIfPresent,
    ),
    metadata_fields: Map([]),
    provider_metadata: Map([]),
    raw_usage: None,
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    response_metadata: None,
    source_index: 0,
    text_started: false,
    metadata_emitted: false,
    output_started: false,
    stream_started: false,
    finalized: false,
  }
}

///|
fn openai_chat_stream_has_output(json : Json) -> Bool {
  match json {
    { "choices": Array(choices), .. } =>
      choices.any(choice => {
        match choice {
          { "delta": Object(delta), .. } =>
            match delta {
              { "content": String(value), .. } if value != "" => true
              { "tool_calls": Array(values), .. } if values.length() > 0 => true
              { "annotations": Array(values), .. } if values.length() > 0 =>
                true
              _ => false
            }
          _ => false
        }
      })
    _ => false
  }
}

///|
fn OpenAIChatStreamDecoder::record_json(
  self : OpenAIChatStreamDecoder,
  json : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  let metadata = openai_chat_response_metadata(json)
  if !metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, metadata),
    )
    if !self.metadata_emitted {
      self.metadata_emitted = true
      events.push(@provider.V4ResponseMetadataReady(metadata))
    }
  }
  self.provider_metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    @provider_utils.provider_metadata_from_json(json, self.provider_name),
  )
  let extracted = openai_chat_metadata_fields(json)
  for entry in extracted.iter2() {
    let (key, value) = entry
    self.metadata_fields[key] = value
  }
}

///|
fn OpenAIChatStreamDecoder::apply_tool_delta(
  self : OpenAIChatStreamDecoder,
  json : Json,
  fallback_index : Int,
  events : Array[@provider.LanguageModelV4StreamPart],
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
  let tool_type = match json {
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
        data=json,
      ),
    ) {
    events.push(event)
  }
}

///|
fn OpenAIChatStreamDecoder::apply_annotations(
  self : OpenAIChatStreamDecoder,
  annotations : Array[Json],
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  for annotation in annotations {
    let generated = (self.generate_id)()
    let source_id = if generated == "" {
      "source-\{self.source_index}"
    } else {
      generated
    }
    self.source_index = self.source_index + 1
    match openai_chat_annotation_content(annotation, source_id) {
      Some(@provider.V4SourceOutput(source)) =>
        events.push(@provider.V4SourceReady(source))
      _ => ()
    }
  }
}

///|
fn OpenAIChatStreamDecoder::apply_json(
  self : OpenAIChatStreamDecoder,
  json : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit raise {
  match json {
    { "usage": Null, .. } => ()
    { "usage": value, .. } => self.raw_usage = Some(value)
    _ => ()
  }
  match json {
    { "choices": [{ "finish_reason": String(reason), .. }, ..], .. } => {
      self.finish_reason = openai_chat_finish_reason(reason)
      self.finish_reason_raw = Some(reason)
    }
    _ => ()
  }
  match json {
    { "choices": [{ "delta": Object(delta), .. }, ..], .. } => {
      match delta {
        { "content": String(value), .. } => {
          if !self.text_started {
            self.text_started = true
            events.push(
              @provider.V4TextStart(id="0", provider_metadata=Map([])),
            )
          }
          self.text.write_string(value)
          events.push(
            @provider.V4TextDelta(
              id="0",
              delta=value,
              provider_metadata=Map([]),
            ),
          )
        }
        _ => ()
      }
      match delta {
        { "tool_calls": Array(values), .. } =>
          for fallback_index, value in values {
            self.apply_tool_delta(value, fallback_index, events)
          }
        _ => ()
      }
      match delta {
        { "annotations": Array(values), .. } =>
          self.apply_annotations(values, events)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
fn OpenAIChatStreamDecoder::final_events(
  self : OpenAIChatStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.text_started {
    events.push(@provider.V4TextEnd(id="0", provider_metadata=Map([])))
  }
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
fn OpenAIChatStreamDecoder::decode_data(
  self : OpenAIChatStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => {
      self.finish_reason = @provider.Error
      self.finish_reason_raw = None
      let events : Array[@provider.LanguageModelV4StreamPart] = [
        @provider.V4Error(
          @provider.StreamErrorInfo::new(
            "OpenAI Chat stream decode error: \{error}; data: \{data}",
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
  if !self.stream_started && openai_stream_error_object(json) is Some(error) {
    let message = @provider_utils.json_string_field(error, "message").unwrap_or(
      "OpenAI stream failed before any output was generated",
    )
    let status_code = openai_stream_error_status(error)
    raise @provider_utils.SseProviderError(
      message~,
      status_code~,
      response_body=json.stringify(),
      is_retryable=@provider_utils.is_retryable_status(status_code),
    )
  }
  if openai_error_message(json) is Some(message) {
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
  if openai_chat_stream_has_output(json) {
    self.output_started = true
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.record_json(json, events)
  self.apply_json(json, events)
  if self.include_raw_chunks {
    events.insert(0, @provider.V4Raw(json))
  }
  { events, consumed_event: true, done: false }
}

///|
fn OpenAIChatStreamDecoder::feed_line(
  self : OpenAIChatStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
fn OpenAIChatStreamDecoder::flush_buffered(
  self : OpenAIChatStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Finish the protocol transform after the transport reports a normal EOF.
fn OpenAIChatStreamDecoder::finish_stream(
  self : OpenAIChatStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    @provider_utils.SseDecodeBatch::empty(true)
  } else {
    { events: self.final_events(), consumed_event: false, done: true }
  }
}

///|
fn OpenAIChatStreamDecoder::provider_metadata_snapshot(
  self : OpenAIChatStreamDecoder,
) -> Map[String, Json] {
  @provider.merge_provider_metadata(
    self.provider_metadata,
    Map([
      (
        openai_provider_metadata_key(self.provider_name),
        Json::object(@provider.copy_provider_metadata(self.metadata_fields)),
      ),
    ]),
  )
}

///|
fn OpenAIChatStreamDecoder::v4_usage(
  self : OpenAIChatStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  openai_chat_v4_usage(self.raw_usage)
}

///|
fn OpenAIChatStreamDecoder::v4_finish_reason(
  self : OpenAIChatStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  @provider.LanguageModelV4FinishReason::from_finish_reason(self.finish_reason).with_raw(
    self.finish_reason_raw,
  )
}

///|
fn OpenAIChatStreamDecoder::response_metadata_snapshot(
  self : OpenAIChatStreamDecoder,
) -> @provider.ResponseMetadata? {
  self.response_metadata
}

///|
fn OpenAIChatStreamDecoder::has_output(self : OpenAIChatStreamDecoder) -> Bool {
  self.output_started
}

///|
fn OpenAIChatStreamDecoder::mark_stream_started(
  self : OpenAIChatStreamDecoder,
) -> Unit {
  self.stream_started = true
}

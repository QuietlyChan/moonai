///|
/// Convert official OpenAI Chat Completions token accounting to the shared
/// provider-neutral representation.
fn openai_chat_usage(json : Json) -> @provider.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
  let output_tokens = @provider_utils.json_int_field(json, "completion_tokens")
  let cached_input_tokens = match json {
    { "prompt_tokens_details": { "cached_tokens": Number(value, ..), .. }, .. } =>
      value.to_int()
    _ => 0
  }
  let cache_write_input_tokens = match json {
    {
      "prompt_tokens_details": { "cache_write_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  let reasoning_tokens = match json {
    {
      "completion_tokens_details": { "reasoning_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  {
    input_tokens,
    output_tokens,
    total_tokens: @provider_utils.json_int_field(
      json,
      "total_tokens",
      default=input_tokens + output_tokens,
    ),
    reasoning_tokens,
    cached_input_tokens,
    cache_write_input_tokens,
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
/// Azure content-filter prelude chunks use `created: 0`; matching AI SDK, that
/// placeholder is not considered response metadata.
fn openai_chat_response_metadata(json : Json) -> @provider.ResponseMetadata {
  let metadata = @provider.ResponseMetadata::from_json(json)
  {
    id: metadata.id,
    model_id: metadata.model_id,
    created_at: match metadata.created_at {
      Some(0) => None
      other => other
    },
    status_code: metadata.status_code,
    headers: metadata.headers,
    body: metadata.body,
  }
}

///|
fn openai_chat_annotation_content(
  annotation : Json,
  source_id : String,
) -> @provider.GeneratedContent? {
  match annotation {
    {
      "type": "url_citation",
      "url_citation": { "url": String(url), "title": String(title), .. },
      ..
    } =>
      Some(@provider.GeneratedContent::url_source(id=source_id, url~, title~))
    { "type": "url_citation", "url_citation": { "url": String(url), .. }, .. } =>
      Some(@provider.GeneratedContent::url_source(id=source_id, url~))
    _ => None
  }
}

///|
fn append_openai_chat_annotations(
  content : Array[@provider.GeneratedContent],
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
/// Decode one non-streaming response using the official OpenAI response
/// contract. This intentionally does not depend on the compatible provider.
fn decode_openai_chat_response(
  json : Json,
  provider_name : String,
  id_generator : @provider_utils.IdGenerator,
) -> @provider.ChatResponse raise {
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
  let content : Array[@provider.GeneratedContent] = []
  let generate_id = id_generator
  match message {
    { "content": String(value), .. } if value != "" =>
      content.push(@provider.GeneratedContent::text(value))
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
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(id~, name~, arguments~),
              ),
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
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(id=generate_id(), name~, arguments~),
              ),
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
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => openai_chat_usage(value)
    _ => @provider.Usage::zero()
  }
  let finish_reason = match choice {
    { "finish_reason": String(value), .. } => openai_chat_finish_reason(value)
    _ => @provider.Unknown("")
  }
  let response_metadata = openai_chat_response_metadata(json)
  let provider_metadata = @provider.merge_provider_metadata(
    @provider_utils.provider_metadata_from_json(json, provider_name),
    openai_chat_metadata(json, provider_name),
  )
  @provider.ChatResponse::from_content(content, usage, finish_reason).with_diagnostics(
    None,
    if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
    provider_metadata,
    [],
  )
}

///|
/// Stateful SSE decoder owned by the official OpenAI Chat Completions model.
priv struct OpenAIChatStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  provider_name : String
  generate_id : @provider_utils.IdGenerator
  text : StringBuilder
  tools : @provider_utils.ToolCallDeltaAssembler
  tool_stream_ids : Array[String]
  sources : Array[@provider.GeneratedSource]
  metadata_fields : Map[String, Json]
  mut provider_metadata : Map[String, Json]
  mut usage : @provider.Usage
  mut finish_reason : @provider.FinishReason
  mut response_metadata : @provider.ResponseMetadata?
  mut source_index : Int
  mut text_started : Bool
  mut metadata_emitted : Bool
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
    tools: @provider_utils.ToolCallDeltaAssembler::new(id_generator~),
    tool_stream_ids: [],
    sources: [],
    metadata_fields: Map([]),
    provider_metadata: Map([]),
    usage: @provider.Usage::zero(),
    finish_reason: @provider.Unknown(""),
    response_metadata: None,
    source_index: 0,
    text_started: false,
    metadata_emitted: false,
    finalized: false,
  }
}

///|
fn openai_chat_finish_reason_is_known(reason : @provider.FinishReason) -> Bool {
  match reason {
    @provider.Unknown(value) => value != ""
    _ => true
  }
}

///|
fn OpenAIChatStreamDecoder::record_json(
  self : OpenAIChatStreamDecoder,
  json : Json,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let metadata = openai_chat_response_metadata(json)
  if !metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, metadata),
    )
    if !self.metadata_emitted {
      self.metadata_emitted = true
      events.push(@provider.ResponseMetadataReady(metadata))
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
fn OpenAIChatStreamDecoder::ensure_tool_stream_id(
  self : OpenAIChatStreamDecoder,
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
fn OpenAIChatStreamDecoder::apply_tool_delta(
  self : OpenAIChatStreamDecoder,
  json : Json,
  fallback_index : Int,
  events : Array[@provider.StreamEvent],
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
fn OpenAIChatStreamDecoder::apply_annotations(
  self : OpenAIChatStreamDecoder,
  annotations : Array[Json],
  events : Array[@provider.StreamEvent],
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
      Some(@provider.GeneratedSourceOutput(source)) => {
        self.sources.push(source)
        events.push(@provider.SourceReady(source))
      }
      _ => ()
    }
  }
}

///|
fn OpenAIChatStreamDecoder::apply_json(
  self : OpenAIChatStreamDecoder,
  json : Json,
  events : Array[@provider.StreamEvent],
) -> Unit raise {
  match json {
    { "usage": Null, .. } => ()
    { "usage": value, .. } => self.usage = openai_chat_usage(value)
    _ => ()
  }
  match json {
    { "choices": [{ "finish_reason": String(reason), .. }, ..], .. } =>
      self.finish_reason = openai_chat_finish_reason(reason)
    _ => ()
  }
  match json {
    { "choices": [{ "delta": Object(delta), .. }, ..], .. } => {
      match delta {
        { "content": String(value), .. } => {
          if !self.text_started {
            self.text_started = true
            events.push(@provider.TextStart("text-0"))
          }
          self.text.write_string(value)
          events.push(@provider.TextDelta(id="text-0", delta=value))
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
) -> Array[@provider.StreamEvent] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.StreamEvent] = []
  if self.text_started {
    events.push(@provider.TextEnd("text-0"))
  }
  if self.finish_reason is @provider.Error {
    for stream_id in self.tool_stream_ids {
      if stream_id != "" {
        events.push(@provider.ToolInputEnd(stream_id))
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
      events.push(@provider.ToolInputEnd(stream_id))
      events.push(@provider.ToolCallReady(call))
    }
  }
  events.push(@provider.Finish(usage=self.usage, reason=self.finish_reason))
  events
}

///|
fn OpenAIChatStreamDecoder::decode_data(
  self : OpenAIChatStreamDecoder,
  data : String,
) -> @provider_utils.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error => {
      self.finish_reason = @provider.Error
      return {
        events: [
          @provider.StreamError(
            "OpenAI Chat stream decode error: \{error}; data: \{data}",
          ),
        ],
        consumed_event: true,
        done: false,
      }
    }
  }
  let events : Array[@provider.StreamEvent] = []
  self.record_json(json, events)
  if openai_error_message(json) is Some(message) {
    self.finish_reason = @provider.Error
    events.push(@provider.StreamError(message))
    for event in self.final_events() {
      events.push(event)
    }
    if self.include_raw_chunks {
      events.insert(0, @provider.Raw(json))
    }
    return { events, consumed_event: true, done: true }
  }
  self.apply_json(json, events)
  if self.include_raw_chunks {
    events.insert(0, @provider.Raw(json))
  }
  { events, consumed_event: true, done: false }
}

///|
fn OpenAIChatStreamDecoder::feed_line(
  self : OpenAIChatStreamDecoder,
  raw : String,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
fn OpenAIChatStreamDecoder::flush_buffered(
  self : OpenAIChatStreamDecoder,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.flush() {
    Some(data) => {
      let batch = self.decode_data(data)
      if batch.done || !openai_chat_finish_reason_is_known(self.finish_reason) {
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
        @provider_utils.DecodeBatch::empty(true)
      } else if openai_chat_finish_reason_is_known(self.finish_reason) {
        { events: self.final_events(), consumed_event: false, done: true }
      } else {
        @provider_utils.DecodeBatch::empty(false)
      }
  }
}

///|
fn OpenAIChatStreamDecoder::provider_metadata(
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
fn OpenAIChatStreamDecoder::response(
  self : OpenAIChatStreamDecoder,
) -> @provider.ChatResponse {
  let content : Array[@provider.GeneratedContent] = []
  let text = self.text.to_string()
  if text != "" {
    content.push(@provider.GeneratedContent::text(text))
  }
  if !(self.finish_reason is @provider.Error) {
    for call in self.tools.calls() {
      content.push(@provider.GeneratedContent::tool_call(call))
    }
  }
  for source in self.sources {
    content.push(@provider.GeneratedSourceOutput(source))
  }
  @provider.ChatResponse::from_content(content, self.usage, self.finish_reason).with_diagnostics(
    None,
    self.response_metadata,
    self.provider_metadata(),
    [],
  )
}

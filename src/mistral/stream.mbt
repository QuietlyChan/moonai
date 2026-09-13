///|
/// Streaming state for the Mistral SSE protocol (thinking/text interleave
/// plus tool-call deltas).
priv struct MistralStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  generate_id : @provider_utils.IdGenerator
  tracker : @provider_utils.StreamingToolCallTracker
  text_stream_id : String
  mut text_started : Bool
  mut reasoning_stream_id : String
  mut first_chunk : Bool
  mut finish_raw : String?
  mut usage : Json?
  mut response_metadata : @provider.ResponseMetadata
  mut finalized : Bool
}

///|
fn MistralStreamDecoder::new(
  include_raw_chunks : Bool,
  generate_id : @provider_utils.IdGenerator,
) -> MistralStreamDecoder {
  MistralStreamDecoder::{
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    generate_id,
    tracker: @provider_utils.StreamingToolCallTracker::new(
      id_generator=generate_id,
    ),
    text_stream_id: "0",
    text_started: false,
    reasoning_stream_id: "",
    first_chunk: true,
    finish_raw: None,
    usage: None,
    response_metadata: @provider.ResponseMetadata::empty(),
    finalized: false,
  }
}

///|
fn MistralStreamDecoder::close_text(
  self : MistralStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.text_started {
    self.text_started = false
    events.push(
      @provider.V4TextEnd(id=self.text_stream_id, provider_metadata=Map([])),
    )
  }
}

///|
fn MistralStreamDecoder::close_reasoning(
  self : MistralStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.reasoning_stream_id != "" {
    events.push(
      @provider.V4ReasoningEnd(
        id=self.reasoning_stream_id,
        provider_metadata=Map([]),
      ),
    )
    self.reasoning_stream_id = ""
  }
}

///|
fn MistralStreamDecoder::invalid_chunk(
  self : MistralStreamDecoder,
  data : Json,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  self.finalized = true
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.include_raw_chunks {
    events.push(@provider.V4Raw(data))
  }
  events.push(
    @provider.V4Error(
      @provider.StreamErrorInfo::new("invalid stream chunk", data~),
    ),
  )
  { events, consumed_event: true, done: true, }
}

///|
fn MistralStreamDecoder::decode_data(
  self : MistralStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  if data.trim() == "[DONE]" {
    self.finalized = true
    return { events: self.final_events(), consumed_event: true, done: true, }
  }
  let value = @json.parse(data) catch {
    _ => return self.invalid_chunk(Json::string(data))
  }
  guard value is Object(fields) else {
    return self.invalid_chunk(Json::string(data))
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.include_raw_chunks {
    events.push(@provider.V4Raw(value))
  }
  if self.first_chunk {
    self.first_chunk = false
    self.response_metadata = mistral_response_metadata(value)
    events.push(@provider.V4ResponseMetadataReady(self.response_metadata))
  }
  match fields.get("usage") {
    Some(Object(_)) => self.usage = fields.get("usage")
    _ => ()
  }
  match fields.get("choices") {
    Some(Array(choices)) if choices.length() > 0 => {
      let choice = choices[0]
      if choice is { "finish_reason": String(reason), .. } {
        self.finish_raw = Some(reason)
      }
      if choice is { "delta": Object(delta), .. } {
        match delta.get("content") {
          Some(Array(parts)) => {
            // Thinking parts arrive inside content arrays; emit reasoning
            // deltas and close any active text first.
            for part in parts {
              match part {
                { "type": "thinking", "thinking": thinking_value, .. } =>
                  match mistral_thinking_text(thinking_value) {
                    Some(reasoning) if reasoning != "" => {
                      self.close_text(events)
                      if self.reasoning_stream_id == "" {
                        self.reasoning_stream_id = (self.generate_id)()
                        events.push(
                          @provider.V4ReasoningStart(
                            id=self.reasoning_stream_id,
                            provider_metadata=Map([]),
                          ),
                        )
                      }
                      events.push(
                        @provider.V4ReasoningDelta(
                          id=self.reasoning_stream_id,
                          delta=reasoning,
                          provider_metadata=Map([]),
                        ),
                      )
                    }
                    _ => ()
                  }
                _ => ()
              }
            }
            match mistral_extract_content(Json::array(parts), []) {
              text if text != "" => {
                self.close_reasoning(events)
                if !self.text_started {
                  self.text_started = true
                  events.push(
                    @provider.V4TextStart(
                      id=self.text_stream_id,
                      provider_metadata=Map([]),
                    ),
                  )
                }
                events.push(
                  @provider.V4TextDelta(
                    id=self.text_stream_id,
                    delta=text,
                    provider_metadata=Map([]),
                  ),
                )
              }
              _ => ()
            }
          }
          Some(String(text)) if text != "" => {
            self.close_reasoning(events)
            if !self.text_started {
              self.text_started = true
              events.push(
                @provider.V4TextStart(
                  id=self.text_stream_id,
                  provider_metadata=Map([]),
                ),
              )
            }
            events.push(
              @provider.V4TextDelta(
                id=self.text_stream_id,
                delta=text,
                provider_metadata=Map([]),
              ),
            )
          }
          _ => ()
        }
        if delta.get("tool_calls") is Some(Array(calls)) {
          for call in calls {
            let tool_delta = match call {
              {
                "index": Number(index, ..),
                "id": String(id),
                "function": {
                  "name": String(name),
                  "arguments": String(arguments),
                  ..
                },
                ..
              } =>
                @provider_utils.StreamingToolCallDelta::{
                  index: Some(index.to_int()),
                  id: Some(id),
                  tool_type: Some("function"),
                  function_name: Some(name),
                  arguments_delta: Some(arguments),
                  provider_metadata: Map([]),
                  data: call,
                }
              {
                "index": Number(index, ..),
                "function": { "arguments": String(arguments), .. },
                ..
              } =>
                @provider_utils.StreamingToolCallDelta::{
                  index: Some(index.to_int()),
                  id: None,
                  tool_type: Some("function"),
                  function_name: None,
                  arguments_delta: Some(arguments),
                  provider_metadata: Map([]),
                  data: call,
                }
              _ => continue
            }
            for event in self.tracker.process_delta_v4(tool_delta) {
              events.push(event)
            }
          }
        }
      }
    }
    _ => ()
  }
  { events, consumed_event: true, done: self.finalized, }
}

///|
fn MistralStreamDecoder::final_events(
  self : MistralStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.close_reasoning(events)
  self.close_text(events)
  for event in self.tracker.flush_v4() {
    events.push(event)
  }
  events.push(
    @provider.V4Finish(
      usage=@provider.LanguageModelV4Usage::from_token_usage_json(self.usage),
      reason=mistral_map_finish_reason(self.finish_raw),
      provider_metadata=Map([]),
    ),
  )
  events
}

///|
fn MistralStreamDecoder::feed_line(
  self : MistralStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn MistralStreamDecoder::flush_buffered(
  self : MistralStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn MistralStreamDecoder::finish_stream(
  self : MistralStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  if self.finalized {
    { events: [], consumed_event: false, done: true, }
  } else {
    self.finalized = true
    { events: self.final_events(), consumed_event: false, done: true, }
  }
}

///|
pub impl @provider.LanguageModelV4 for MistralChatLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let (body, warnings) = self.prepare(options)
  let stream_body = match body {
    Object(fields) => {
      let streamed : Map[String, Json] = Map([])
      for entry in fields.iter2() {
        streamed[entry.0] = entry.1
      }
      streamed["stream"] = Json::boolean(true)
      Json::object(streamed)
    }
    other => other
  }
  let decoder = MistralStreamDecoder::new(
    options.include_raw_chunks,
    self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat/completions"),
    headers=self.mistral_request_headers(extra=options.headers),
    body=stream_body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=mistral_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    finish_stream=() => decoder.finish_stream(),
    response=() => decoder.response_metadata,
    transport=self.http_transport,
    on_event~,
  )
  let response_metadata = @provider.merge_response_metadata(
    Some(result.value),
    result.response,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(response_metadata),
  )
}

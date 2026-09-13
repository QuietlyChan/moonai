///|
/// Streaming state for the xAI SSE protocol (OpenAI-shaped deltas plus
/// citations on the first chunk).
priv struct XaiStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  generate_id : @provider_utils.IdGenerator
  tracker : @provider_utils.StreamingToolCallTracker
  text_stream_id : String
  mut text_started : Bool
  mut first_chunk : Bool
  mut finish_raw : String?
  mut usage : Json?
  mut response_metadata : @provider.ResponseMetadata
  mut finalized : Bool
}

///|
fn XaiStreamDecoder::new(
  include_raw_chunks : Bool,
  generate_id : @provider_utils.IdGenerator,
) -> XaiStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    generate_id,
    tracker: @provider_utils.StreamingToolCallTracker::new(
      id_generator=generate_id,
    ),
    text_stream_id: "0",
    text_started: false,
    first_chunk: true,
    finish_raw: None,
    usage: None,
    response_metadata: @provider.ResponseMetadata::empty(),
    finalized: false,
  }
}

///|
fn XaiStreamDecoder::invalid_chunk(
  self : XaiStreamDecoder,
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
fn XaiStreamDecoder::final_events(
  self : XaiStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.text_started {
    self.text_started = false
    events.push(
      @provider.V4TextEnd(id=self.text_stream_id, provider_metadata=Map([])),
    )
  }
  for event in self.tracker.flush_v4() {
    events.push(event)
  }
  events.push(
    @provider.V4Finish(
      usage=@provider.LanguageModelV4Usage::from_token_usage_json(self.usage),
      reason=xai_map_finish_reason(self.finish_raw),
      provider_metadata=Map([]),
    ),
  )
  events
}

///|
fn XaiStreamDecoder::decode_data(
  self : XaiStreamDecoder,
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
    self.response_metadata = xai_response_metadata(value)
    events.push(@provider.V4ResponseMetadataReady(self.response_metadata))
    for url in xai_citations(value) {
      events.push(
        @provider.V4SourceReady(
          @provider.V4UrlSource(
            id=(self.generate_id)(),
            url~,
            title=None,
            provider_metadata=Map([]),
          ),
        ),
      )
    }
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
          Some(String(text)) if text != "" => {
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
fn XaiStreamDecoder::feed_line(
  self : XaiStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn XaiStreamDecoder::flush_buffered(
  self : XaiStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn XaiStreamDecoder::finish_stream(
  self : XaiStreamDecoder,
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
pub impl @provider.LanguageModelV4 for XaiChatLanguageModel with fn do_stream(
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
      streamed["stream_options"] = { "include_usage": true }
      Json::object(streamed)
    }
    other => other
  }
  let decoder = XaiStreamDecoder::new(
    options.include_raw_chunks,
    self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat/completions"),
    headers=xai_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=stream_body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=xai_error_to_message,
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

///|
/// Streaming state for the Perplexity SSE protocol.
priv struct PerplexityStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  generate_id : @provider_utils.IdGenerator
  text_stream_id : String
  mut text_started : Bool
  mut first_chunk : Bool
  mut finish_raw : String?
  mut usage : Json?
  mut provider_metadata : Map[String, Json]
  mut response_metadata : @provider.ResponseMetadata
  mut finalized : Bool
}

///|
fn PerplexityStreamDecoder::new(
  include_raw_chunks : Bool,
  generate_id : @provider_utils.IdGenerator,
) -> PerplexityStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    generate_id,
    text_stream_id: "0",
    text_started: false,
    first_chunk: true,
    finish_raw: None,
    usage: None,
    provider_metadata: Map([]),
    response_metadata: @provider.ResponseMetadata::empty(),
    finalized: false,
  }
}

///|
fn PerplexityStreamDecoder::invalid_chunk(
  self : PerplexityStreamDecoder,
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
fn PerplexityStreamDecoder::decode_data(
  self : PerplexityStreamDecoder,
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
    self.response_metadata = perplexity_response_metadata(value)
    events.push(@provider.V4ResponseMetadataReady(self.response_metadata))
    for url in perplexity_citations(value) {
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
    Some(Object(_)) => {
      self.usage = fields.get("usage")
      self.provider_metadata = perplexity_provider_metadata(value)
    }
    _ => ()
  }
  match fields.get("images") {
    Some(Array(images)) if images.length() > 0 => {
      let merged = perplexity_provider_metadata(value)
      if merged.get("perplexity") is Some(Object(extra)) &&
        extra.get("images") is Some(_) {
        self.provider_metadata = merged
      }
    }
    _ => ()
  }
  match fields.get("choices") {
    Some(Array(choices)) if choices.length() > 0 =>
      match choices[0] {
        { "finish_reason": String(reason), .. } =>
          self.finish_raw = Some(reason)
        { "delta": Object(delta), .. } =>
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
        _ => ()
      }
    _ => ()
  }
  { events, consumed_event: true, done: self.finalized, }
}

///|
fn PerplexityStreamDecoder::final_events(
  self : PerplexityStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.text_started {
    self.text_started = false
    events.push(
      @provider.V4TextEnd(id=self.text_stream_id, provider_metadata=Map([])),
    )
  }
  events.push(
    @provider.V4Finish(
      usage=@provider.LanguageModelV4Usage::from_token_usage_json(self.usage),
      reason=perplexity_map_finish_reason(self.finish_raw),
      provider_metadata=self.provider_metadata,
    ),
  )
  events
}

///|
fn PerplexityStreamDecoder::feed_line(
  self : PerplexityStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn PerplexityStreamDecoder::flush_buffered(
  self : PerplexityStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn PerplexityStreamDecoder::finish_stream(
  self : PerplexityStreamDecoder,
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
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let (body, warnings) = self.perplexity_prepare(options)
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
  let decoder = PerplexityStreamDecoder::new(
    options.include_raw_chunks,
    self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat/completions"),
    headers=perplexity_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=stream_body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=perplexity_error_to_message,
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

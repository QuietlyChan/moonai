///|
/// Streaming state for Gemini's streamGenerateContent SSE protocol. Each SSE
/// payload carries the same shape as a generateContent response; deltas are
/// reconstructed by diffing parts against previously emitted text lengths.
priv struct GoogleStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  mut text_started : Bool
  text_stream_id : String
  mut finish_raw : String?
  mut usage : Json?
  mut finalized : Bool
}

///|
fn GoogleStreamDecoder::new(
  include_raw_chunks : Bool,
  generate_id : @provider_utils.IdGenerator,
) -> GoogleStreamDecoder {
  ignore(generate_id)
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    text_started: false,
    text_stream_id: "0",
    finish_raw: None,
    usage: None,
    finalized: false,
  }
}

///|
fn GoogleStreamDecoder::invalid_chunk(
  self : GoogleStreamDecoder,
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
fn GoogleStreamDecoder::final_events(
  self : GoogleStreamDecoder,
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
      usage=google_usage(self.usage),
      reason=google_map_finish_reason(self.finish_raw),
      provider_metadata=Map([]),
    ),
  )
  events
}

///|
fn GoogleStreamDecoder::decode_data(
  self : GoogleStreamDecoder,
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
  if fields.get("usageMetadata") is Some(Object(_)) {
    self.usage = fields.get("usageMetadata")
  }
  if fields.get("promptFeedback") is Some({ "blockReason": String(reason), .. }) {
    self.finish_raw = Some(reason)
  }
  if fields.get("candidates") is Some(Array(candidates)) &&
    candidates.length() > 0 {
    match candidates[0] {
      { "finishReason": String(reason), .. } => self.finish_raw = Some(reason)
      _ => ()
    }
    if candidates[0] is { "content": { "parts": Array(parts), .. }, .. } {
      for part in parts {
        match part {
          { "text": String(text), .. } if text != "" => {
            // Each SSE payload carries incremental text for the turn.
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
    }
  }
  { events, consumed_event: true, done: self.finalized, }
}

///|
fn GoogleStreamDecoder::feed_line(
  self : GoogleStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn GoogleStreamDecoder::flush_buffered(
  self : GoogleStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn GoogleStreamDecoder::finish_stream(
  self : GoogleStreamDecoder,
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
pub impl @provider.LanguageModelV4 for GoogleChatLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let (body, warnings) = self.prepare(options)
  let decoder = GoogleStreamDecoder::new(
    options.include_raw_chunks,
    self.id_generator,
  )
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url="\{self.base_url}/\{get_model_path(self.model_id)}:streamGenerateContent?alt=sse",
    headers=@provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(
        @provider_utils.merge_headers(
          Map([
            (
              "x-goog-api-key",
              @provider_utils.load_api_key(
                self.api_key,
                environment_variable_name="GOOGLE_GENERATIVE_AI_API_KEY",
                description="Google Gemini",
              ),
            ),
            ("Content-Type", "application/json"),
          ]),
          self.headers,
        ),
        options.headers,
      ),
      ["ai-sdk/\{self.provider_name}/\{VERSION}"],
    ),
    body~,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=google_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    finish_stream=() => decoder.finish_stream(),
    response=() => @provider.ResponseMetadata::empty(),
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

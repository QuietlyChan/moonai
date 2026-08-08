///|
fn openai_completion_v4_usage(
  raw_usage : Json?,
) -> @provider.LanguageModelV4Usage {
  match raw_usage {
    Some(json) if !(json is Null) => {
      let input_total = match json {
        { "prompt_tokens": Number(value, ..), .. } => Some(value.to_int())
        _ => None
      }
      let output_total = match json {
        { "completion_tokens": Number(value, ..), .. } => Some(value.to_int())
        _ => None
      }
      {
        input_tokens: {
          total: input_total,
          no_cache: Some(input_total.unwrap_or(0)),
          cache_read: None,
          cache_write: None,
        },
        output_tokens: {
          total: output_total,
          text: Some(output_total.unwrap_or(0)),
          reasoning: None,
        },
        raw: Some(json),
      }
    }
    _ => @provider_utils.create_null_language_model_usage()
  }
}

///|
/// Stateful SSE decoder owned by the official OpenAI completion model.
priv struct OpenAICompletionStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  text : StringBuilder
  mut raw_usage : Json?
  mut finish_reason : @provider.FinishReason
  mut finish_reason_raw : String?
  mut response_metadata : @provider.ResponseMetadata?
  mut logprobs : Json?
  mut text_started : Bool
  mut metadata_emitted : Bool
  mut output_started : Bool
  mut stream_started : Bool
  mut finalized : Bool
}

///|
fn OpenAICompletionStreamDecoder::new(
  include_raw_chunks~ : Bool,
) -> OpenAICompletionStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    text: StringBuilder::new(),
    raw_usage: None,
    finish_reason: @provider.Unknown(""),
    finish_reason_raw: None,
    response_metadata: None,
    logprobs: None,
    text_started: false,
    metadata_emitted: false,
    output_started: false,
    stream_started: false,
    finalized: false,
  }
}

///|
fn OpenAICompletionStreamDecoder::record_json(
  self : OpenAICompletionStreamDecoder,
  json : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  let metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created"),
  )
  if !metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, metadata),
    )
  }
  if !self.metadata_emitted {
    self.metadata_emitted = true
    events.push(@provider.V4ResponseMetadataReady(metadata))
    self.text_started = true
    events.push(@provider.V4TextStart(id="0", provider_metadata=Map([])))
  }
  match json {
    { "choices": [{ "logprobs": value, .. }, ..], .. } if !(value is Null) =>
      self.logprobs = Some(value)
    _ => ()
  }
}

///|
fn OpenAICompletionStreamDecoder::apply_json(
  self : OpenAICompletionStreamDecoder,
  json : Json,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  match json {
    { "usage": Null, .. } => ()
    { "usage": value, .. } => self.raw_usage = Some(value)
    _ => ()
  }
  match json {
    { "choices": [{ "text": String(value), .. }, ..], .. } if value != "" => {
      self.text.write_string(value)
      events.push(
        @provider.V4TextDelta(id="0", delta=value, provider_metadata=Map([])),
      )
    }
    _ => ()
  }
  match json {
    { "choices": [{ "finish_reason": String(reason), .. }, ..], .. } => {
      self.finish_reason = @provider.FinishReason::from_openai(reason)
      self.finish_reason_raw = Some(reason)
    }
    _ => ()
  }
  events
}

///|
fn OpenAICompletionStreamDecoder::final_events(
  self : OpenAICompletionStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.text_started {
    events.push(@provider.V4TextEnd(id="0", provider_metadata=Map([])))
  }
  events.push(
    @provider.V4Finish(
      usage=self.v4_usage(),
      reason=self.v4_finish_reason(),
      provider_metadata=self.provider_metadata(),
    ),
  )
  events
}

///|
fn OpenAICompletionStreamDecoder::decode_data(
  self : OpenAICompletionStreamDecoder,
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
            "OpenAI completion stream decode error: \{error}; data: \{data}",
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
  match json {
    { "choices": Array(choices), .. } if choices.any(choice => {
        match choice {
          { "text": String(value), .. } => value != ""
          _ => false
        }
      }) => self.output_started = true
    _ => ()
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.record_json(json, events)
  let decoded_events = self.apply_json(json)
  for event in decoded_events {
    events.push(event)
  }
  if self.include_raw_chunks {
    let raw_events : Array[@provider.LanguageModelV4StreamPart] = [
      @provider.V4Raw(json),
    ]
    for event in events {
      raw_events.push(event)
    }
    { events: raw_events, consumed_event: true, done: false }
  } else {
    { events, consumed_event: true, done: false }
  }
}

///|
fn OpenAICompletionStreamDecoder::feed_line(
  self : OpenAICompletionStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
fn OpenAICompletionStreamDecoder::flush_buffered(
  self : OpenAICompletionStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Finish the protocol transform after the transport reports a normal EOF.
fn OpenAICompletionStreamDecoder::finish_stream(
  self : OpenAICompletionStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    @provider_utils.SseDecodeBatch::empty(true)
  } else {
    { events: self.final_events(), consumed_event: false, done: true }
  }
}

///|
fn OpenAICompletionStreamDecoder::provider_metadata(
  self : OpenAICompletionStreamDecoder,
) -> Map[String, Json] {
  match self.logprobs {
    Some(value) => Map([("openai", ({ "logprobs": value } : Json))])
    None => Map([("openai", Json::empty_object())])
  }
}

///|
fn OpenAICompletionStreamDecoder::v4_usage(
  self : OpenAICompletionStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  openai_completion_v4_usage(self.raw_usage)
}

///|
fn OpenAICompletionStreamDecoder::v4_finish_reason(
  self : OpenAICompletionStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  @provider.LanguageModelV4FinishReason::from_finish_reason(self.finish_reason).with_raw(
    self.finish_reason_raw,
  )
}

///|
fn OpenAICompletionStreamDecoder::response_metadata_snapshot(
  self : OpenAICompletionStreamDecoder,
) -> @provider.ResponseMetadata? {
  self.response_metadata
}

///|
fn OpenAICompletionStreamDecoder::has_output(
  self : OpenAICompletionStreamDecoder,
) -> Bool {
  self.output_started
}

///|
fn OpenAICompletionStreamDecoder::mark_stream_started(
  self : OpenAICompletionStreamDecoder,
) -> Unit {
  self.stream_started = true
}

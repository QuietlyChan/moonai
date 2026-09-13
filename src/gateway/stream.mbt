///|
/// Streaming state for the gateway SSE protocol: each data payload is a
/// LanguageModelV4StreamPart JSON object.
priv struct GatewayStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  mut finish_raw : String?
  mut usage : Json?
  mut finalized : Bool
}

///|
fn GatewayStreamDecoder::new(include_raw_chunks : Bool) -> GatewayStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    finish_raw: None,
    usage: None,
    finalized: false,
  }
}

///|
fn GatewayStreamDecoder::decode_part(
  self : GatewayStreamDecoder,
  value : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Bool {
  // Returns false when the chunk is not a recognized stream part.
  let kind = match value {
    { "type": String(kind), .. } => kind
    _ => return false
  }
  match kind {
    "stream-start" => ()
    "text-start" =>
      match value {
        { "id": String(id), .. } =>
          events.push(@provider.V4TextStart(id~, provider_metadata=Map([])))
        _ => ()
      }
    "text-delta" =>
      match value {
        { "id": String(id), "delta": String(delta), .. } =>
          events.push(
            @provider.V4TextDelta(id~, delta~, provider_metadata=Map([])),
          )
        _ => ()
      }
    "text-end" =>
      match value {
        { "id": String(id), .. } =>
          events.push(@provider.V4TextEnd(id~, provider_metadata=Map([])))
        _ => ()
      }
    "reasoning-start" =>
      match value {
        { "id": String(id), .. } =>
          events.push(
            @provider.V4ReasoningStart(id~, provider_metadata=Map([])),
          )
        _ => ()
      }
    "reasoning-delta" =>
      match value {
        { "id": String(id), "delta": String(delta), .. } =>
          events.push(
            @provider.V4ReasoningDelta(id~, delta~, provider_metadata=Map([])),
          )
        _ => ()
      }
    "reasoning-end" =>
      match value {
        { "id": String(id), .. } =>
          events.push(@provider.V4ReasoningEnd(id~, provider_metadata=Map([])))
        _ => ()
      }
    "tool-input-start" =>
      match value {
        { "id": String(id), "toolName": String(tool_name), .. } =>
          events.push(
            @provider.V4ToolInputStart(
              id~,
              tool_name~,
              provider_executed=false,
              dynamic=false,
              title=None,
              provider_metadata=Map([]),
            ),
          )
        _ => ()
      }
    "tool-input-delta" =>
      match value {
        { "id": String(id), "delta": String(delta), .. } =>
          events.push(
            @provider.V4ToolInputDelta(id~, delta~, provider_metadata=Map([])),
          )
        _ => ()
      }
    "tool-input-end" =>
      match value {
        { "id": String(id), .. } =>
          events.push(@provider.V4ToolInputEnd(id~, provider_metadata=Map([])))
        _ => ()
      }
    "tool-call" =>
      match value {
        {
          "toolCallId": String(tool_call_id),
          "toolName": String(tool_name),
          ..
        } => {
          let input_value = match value {
            Object(fields) => fields.get("input")
            _ => None
          }
          let input = match input_value {
            Some(Object(_)) =>
              input_value.unwrap_or(Json::object(Map([]))).stringify()
            _ => "{}"
          }
          events.push(
            @provider.V4ToolCallReady({
              tool_call_id,
              tool_name,
              input,
              provider_executed: value is { "providerExecuted": True, .. },
              dynamic: false,
              provider_metadata: Map([]),
            }),
          )
        }
        _ => ()
      }
    "response-metadata" =>
      events.push(
        @provider.V4ResponseMetadataReady({
          ..@provider.ResponseMetadata::empty(),
          id: match value {
            { "id": String(id), .. } => Some(id)
            _ => None
          },
        }),
      )
    "finish" => {
      self.usage = match value {
        Object(fields) => fields.get("usage")
        _ => None
      }
      match value {
        Object(fields) =>
          match fields.get("finishReason") {
            Some({ "raw": String(raw), .. }) => self.finish_raw = Some(raw)
            _ => ()
          }
        _ => ()
      }
      events.push(
        @provider.V4Finish(
          usage=gateway_usage(self.usage),
          reason={ unified: @provider.V4FinishOther, raw: self.finish_raw, },
          provider_metadata=Map([]),
        ),
      )
      self.finalized = true
    }
    "error" =>
      events.push(
        @provider.V4Error(
          @provider.StreamErrorInfo::new("gateway stream error", data=value),
        ),
      )
    _ => return false
  }
  true
}

///|
fn GatewayStreamDecoder::decode_data(
  self : GatewayStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  if data.trim() == "[DONE]" {
    self.finalized = true
    return { events: [], consumed_event: true, done: true, }
  }
  let value = @json.parse(data) catch {
    _ => return self.invalid_chunk(Json::string(data))
  }
  guard value is Object(_) else {
    return self.invalid_chunk(Json::string(data))
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  let kind = match value {
    { "type": String(kind), .. } => kind
    _ => ""
  }
  if kind == "raw" {
    if self.include_raw_chunks {
      events.push(@provider.V4Raw(value))
    }
    return { events, consumed_event: true, done: self.finalized, }
  }
  if self.decode_part(value, events) {
    return { events, consumed_event: true, done: self.finalized, }
  }
  self.invalid_chunk(Json::string(data))
}

///|
fn GatewayStreamDecoder::invalid_chunk(
  self : GatewayStreamDecoder,
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
fn GatewayStreamDecoder::feed_line(
  self : GatewayStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn GatewayStreamDecoder::flush_buffered(
  self : GatewayStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn GatewayStreamDecoder::finish_stream(
  self : GatewayStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  if self.finalized {
    { events: [], consumed_event: false, done: true, }
  } else {
    self.finalized = true
    { events: [], consumed_event: false, done: true, }
  }
}

///|
pub impl @provider.LanguageModelV4 for GatewayLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let body = gateway_encode_options(options)
  let decoder = GatewayStreamDecoder::new(options.include_raw_chunks)
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=self.gateway_language_model_url(),
    headers=self.request_headers(extra=options.headers, streaming=true),
    body~,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    start_events=[@provider.V4StreamStart(warnings=[])],
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

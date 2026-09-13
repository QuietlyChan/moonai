///|
/// Streaming state for Cohere's typed event SSE protocol.
priv struct CohereStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  mut finish_raw : String?
  mut usage : Json?
  mut response_id : String?
  mut finalized : Bool
  mut pending_tool_call : (String, String, StringBuilder)?
}

///|
fn CohereStreamDecoder::new(include_raw_chunks : Bool) -> CohereStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    finish_raw: None,
    usage: None,
    response_id: None,
    finalized: false,
    pending_tool_call: None,
  }
}

///|
fn CohereStreamDecoder::invalid_chunk(
  self : CohereStreamDecoder,
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
/// Decode a tool-call arguments accumulator into a ready tool call.
fn cohere_tool_call_from_pending(
  id : String,
  name : String,
  arguments : StringBuilder,
) -> @provider.LanguageModelV4StreamPart {
  let text = arguments.to_string()
  let trimmed = text.trim()
  let input_json = @json.parse(if trimmed == "" { "{}" } else { trimmed }) catch {
    _ => Json::object(Map([]))
  }
  @provider.V4ToolCallReady({
    tool_call_id: id,
    tool_name: name,
    input: input_json.stringify(),
    provider_executed: false,
    dynamic: false,
    provider_metadata: Map([]),
  })
}

///|
fn CohereStreamDecoder::decode_data(
  self : CohereStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  if data.trim() == "[DONE]" {
    self.finalized = true
    let events : Array[@provider.LanguageModelV4StreamPart] = [
      @provider.V4Finish(
        usage=cohere_usage(self.usage),
        reason=cohere_map_finish_reason(self.finish_raw),
        provider_metadata=Map([]),
      ),
    ]
    return { events, consumed_event: true, done: true, }
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
  let event_type = match fields.get("type") {
    Some(String(kind)) => kind
    _ => ""
  }
  let delta = fields.get("delta")
  if event_type == "message-start" {
    match fields.get("id") {
      Some(String(id)) => self.response_id = Some(id)
      _ => ()
    }
    events.push(
      @provider.V4ResponseMetadataReady({
        ..@provider.ResponseMetadata::empty(),
        id: self.response_id,
      }),
    )
  } else if event_type == "message-end" {
    match delta {
      Some(Object(delta_fields)) => {
        match delta_fields.get("finish_reason") {
          Some(String(reason)) => self.finish_raw = Some(reason)
          _ => ()
        }
        self.usage = delta_fields.get("usage")
      }
      _ => ()
    }
  } else if event_type == "content-start" {
    let thinking = delta
      is Some({ "message": { "content": { "type": "thinking", .. }, .. }, .. })
    let index = cohere_stream_index(fields)
    if thinking {
      events.push(
        @provider.V4ReasoningStart(id=index, provider_metadata=Map([])),
      )
    } else {
      events.push(@provider.V4TextStart(id=index, provider_metadata=Map([])))
    }
  } else if event_type == "content-delta" {
    let index = cohere_stream_index(fields)
    match delta {
      Some(
        { "message": { "content": { "thinking": String(text), .. }, .. }, .. } as _pattern
      ) => {
        ignore(_pattern)
        events.push(
          @provider.V4ReasoningDelta(
            id=index,
            delta=text,
            provider_metadata=Map([]),
          ),
        )
      }
      Some({ "message": { "content": { "text": String(text), .. }, .. }, .. }) =>
        events.push(
          @provider.V4TextDelta(id=index, delta=text, provider_metadata=Map([])),
        )
      _ => ()
    }
  } else if event_type == "content-end" {
    events.push(
      @provider.V4TextEnd(
        id=cohere_stream_index(fields),
        provider_metadata=Map([]),
      ),
    )
  } else if event_type == "tool-call-start" {
    match delta {
      Some({ "message": { "tool_calls": Object(tool_calls), .. }, .. }) => {
        let (id, name, initial_args) = cohere_tool_call_fields(
          Json::object(tool_calls),
        )
        self.pending_tool_call = Some((id, name, StringBuilder()))
        events.push(
          @provider.V4ToolInputStart(
            id~,
            tool_name=name,
            provider_executed=false,
            dynamic=false,
            title=None,
            provider_metadata=Map([]),
          ),
        )
        if initial_args != "" {
          match self.pending_tool_call {
            Some((_, _, builder)) => builder.write_string(initial_args)
            None => ()
          }
          events.push(
            @provider.V4ToolInputDelta(
              id~,
              delta=initial_args,
              provider_metadata=Map([]),
            ),
          )
        }
      }
      _ => ()
    }
  } else if event_type == "tool-call-delta" {
    match (self.pending_tool_call, delta) {
      (
        Some((id, _, builder)),
        Some(
          {
            "message": {
              "tool_calls": {
                "function": { "arguments": String(args_delta), .. },
                ..
              },
              ..
            },
            ..
          }
        ),
      ) => {
        builder.write_string(args_delta)
        events.push(
          @provider.V4ToolInputDelta(
            id~,
            delta=args_delta,
            provider_metadata=Map([]),
          ),
        )
      }
      _ => ()
    }
  } else if event_type == "tool-call-end" {
    match self.pending_tool_call {
      Some((id, name, builder)) => {
        events.push(@provider.V4ToolInputEnd(id~, provider_metadata=Map([])))
        events.push(cohere_tool_call_from_pending(id, name, builder))
        self.pending_tool_call = None
      }
      None => ()
    }
  }
  { events, consumed_event: true, done: self.finalized, }
}

///|
fn cohere_stream_index(fields : Map[String, Json]) -> String {
  match fields.get("index") {
    Some(Number(value, ..)) => value.to_int().to_string()
    _ => "0"
  }
}

///|
/// Extract `(id, name, initial_arguments)` from a Cohere tool call object.
fn cohere_tool_call_fields(tool_calls : Json) -> (String, String, String) {
  match tool_calls {
    {
      "id": String(id),
      "function": { "name": String(name), "arguments": String(arguments), .. },
      ..
    } => (id, name, arguments)
    _ => ("", "", "")
  }
}

///|
fn CohereStreamDecoder::final_events(
  self : CohereStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  [
    @provider.V4Finish(
      usage=cohere_usage(self.usage),
      reason=cohere_map_finish_reason(self.finish_raw),
      provider_metadata=Map([]),
    ),
  ]
}

///|
fn CohereStreamDecoder::feed_line(
  self : CohereStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn CohereStreamDecoder::flush_buffered(
  self : CohereStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => { events: [], consumed_event: false, done: self.finalized, }
  }
}

///|
fn CohereStreamDecoder::finish_stream(
  self : CohereStreamDecoder,
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
pub impl @provider.LanguageModelV4 for CohereChatLanguageModel with fn do_stream(
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
  let decoder = CohereStreamDecoder::new(options.include_raw_chunks)
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat"),
    headers=cohere_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=stream_body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=cohere_error_to_message,
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

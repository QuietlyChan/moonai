///|
/// A Perplexity Agent API SSE decoder. Open Responses-style output events are
/// mapped here alongside Perplexity's reasoning and native search events.
priv struct PerplexityAgentStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  id_generator : @provider_utils.IdGenerator
  text_ids : Array[String]
  text_values : Array[StringBuilder]
  text_ended : Array[Bool]
  mut active_reasoning_id : String?
  source_urls : Array[String]
  pending_source_urls : Array[String]
  pending_sources : Array[@provider.LanguageModelV4Source]
  function_call_ids : Array[String]
  search_queries : Array[String]
  mut response_metadata : @provider.ResponseMetadata?
  mut response_metadata_emitted : Bool
  mut usage : Json?
  mut finish_reason : @provider.LanguageModelV4FinishReason
  mut finalized : Bool
}

///|
fn PerplexityAgentStreamDecoder::new(
  include_raw_chunks : Bool,
  id_generator : @provider_utils.IdGenerator,
) -> PerplexityAgentStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    id_generator,
    text_ids: [],
    text_values: [],
    text_ended: [],
    active_reasoning_id: None,
    source_urls: [],
    pending_source_urls: [],
    pending_sources: [],
    function_call_ids: [],
    search_queries: [],
    response_metadata: None,
    response_metadata_emitted: false,
    usage: None,
    finish_reason: @provider.LanguageModelV4FinishReason::unknown(),
    finalized: false,
  }
}

///|
fn PerplexityAgentStreamDecoder::response_metadata_from(
  self : PerplexityAgentStreamDecoder,
  value : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.response_metadata_emitted {
    return
  }
  let metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(value, "id"),
    model?=@provider_utils.json_string_field(value, "model"),
    created?=@provider_utils.json_int_field_opt(value, "created_at"),
  )
  self.response_metadata = Some(metadata)
  self.response_metadata_emitted = true
  if !metadata.is_empty() {
    events.push(@provider.V4ResponseMetadataReady(metadata))
  }
}

///|
fn PerplexityAgentStreamDecoder::text_state_index(
  self : PerplexityAgentStreamDecoder,
  id : String,
) -> Int32? {
  for index, value in self.text_ids {
    if value == id {
      return Some(index)
    }
  }
  None
}

///|
fn perplexity_agent_text_id(
  item_id : String?,
  output_index : Int32?,
  content_index : Int32?,
) -> String {
  let id = item_id.unwrap_or(
    output_index.map(value => value.to_string()).unwrap_or("text"),
  )
  let index = content_index.unwrap_or(0)
  if index == 0 {
    id
  } else {
    "\{id}:\{index}"
  }
}

///|
fn PerplexityAgentStreamDecoder::emit_text_delta(
  self : PerplexityAgentStreamDecoder,
  id : String,
  delta : String,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if delta == "" {
    return
  }
  let index = match self.text_state_index(id) {
    Some(index) if self.text_ended[index] => return
    Some(index) => index
    None => {
      self.text_ids.push(id)
      self.text_values.push(StringBuilder())
      self.text_ended.push(false)
      let created = self.text_ids.length() - 1
      events.push(@provider.V4TextStart(id~, provider_metadata=Map([])))
      created
    }
  }
  self.text_values[index].write_string(delta)
  events.push(@provider.V4TextDelta(id~, delta~, provider_metadata=Map([])))
}

///|
fn PerplexityAgentStreamDecoder::finish_text(
  self : PerplexityAgentStreamDecoder,
  id : String,
  final_text : String?,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  let index = match self.text_state_index(id) {
    Some(index) if self.text_ended[index] => return
    Some(index) => index
    None => {
      match final_text {
        Some(value) if value != "" => self.emit_text_delta(id, value, events)
        _ => return
      }
      self.text_state_index(id).unwrap()
    }
  }
  match final_text {
    Some(value) => {
      let emitted = self.text_values[index].to_string()
      if value.has_prefix(emitted) && value.length() > emitted.length() {
        self.emit_text_delta(id, value[emitted.length():].to_owned(), events)
      }
    }
    None => ()
  }
  self.text_ended[index] = true
  events.push(@provider.V4TextEnd(id~, provider_metadata=Map([])))
}

///|
fn perplexity_agent_source_has_result_id(
  source : @provider.LanguageModelV4Source,
) -> Bool {
  match source {
    @provider.V4UrlSource(provider_metadata~, ..) =>
      match provider_metadata.get("perplexity") {
        Some({ "resultId": Number(_, ..), .. }) => true
        _ => false
      }
    _ => false
  }
}

///|
fn PerplexityAgentStreamDecoder::emit_source(
  self : PerplexityAgentStreamDecoder,
  source : @provider.LanguageModelV4Source,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  let url = match source {
    @provider.V4UrlSource(url~, ..) => url
    _ => return
  }
  if self.source_urls.contains(url) {
    return
  }
  let pending_index : Int32? = {
    let mut found : Int32? = None
    for index, pending_url in self.pending_source_urls {
      if pending_url == url {
        found = Some(index)
      }
    }
    found
  }
  match pending_index {
    Some(index) if perplexity_agent_source_has_result_id(source) => {
      self.pending_sources[index] = source
      let upgraded = self.pending_sources[index]
      ignore(self.pending_sources.remove(index))
      ignore(self.pending_source_urls.remove(index))
      self.source_urls.push(url)
      events.push(@provider.V4SourceReady(upgraded))
    }
    Some(_) => ()
    None if perplexity_agent_source_has_result_id(source) => {
      self.source_urls.push(url)
      events.push(@provider.V4SourceReady(source))
    }
    None => {
      self.pending_source_urls.push(url)
      self.pending_sources.push(source)
    }
  }
}

///|
fn PerplexityAgentStreamDecoder::flush_sources(
  self : PerplexityAgentStreamDecoder,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  for index, source in self.pending_sources {
    let url = self.pending_source_urls[index]
    if !self.source_urls.contains(url) {
      self.source_urls.push(url)
      events.push(@provider.V4SourceReady(source))
    }
  }
  self.pending_sources.clear()
  self.pending_source_urls.clear()
}

///|
fn PerplexityAgentStreamDecoder::emit_annotations(
  self : PerplexityAgentStreamDecoder,
  part : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  match part {
    { "annotations": Array(annotations), .. } =>
      for annotation in annotations {
        match
          perplexity_agent_annotation_source(annotation, self.id_generator) {
          Some(@provider.V4SourceOutput(source)) =>
            self.emit_source(source, events)
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn PerplexityAgentStreamDecoder::emit_function_call(
  self : PerplexityAgentStreamDecoder,
  item : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  match item {
    {
      "type": "function_call",
      "call_id": String(call_id),
      "name": String(name),
      "arguments": String(arguments),
      ..
    } if !self.function_call_ids.contains(call_id) => {
      self.function_call_ids.push(call_id)
      let item_id = @provider_utils.json_string_field(item, "id")
      let signature = @provider_utils.json_string_field(
        item, "thought_signature",
      )
      let metadata : Map[String, Json] = Map([
        ("itemId", item_id.map(Json::string).unwrap_or(Json::null())),
        (
          "thoughtSignature",
          signature.map(Json::string).unwrap_or(Json::null()),
        ),
      ])
      let provider_metadata = Map([("perplexity", Json::object(metadata))])
      events.push(
        @provider.V4ToolInputStart(
          id=call_id,
          tool_name=name,
          provider_executed=false,
          dynamic=false,
          title=None,
          provider_metadata~,
        ),
      )
      if arguments != "" {
        events.push(
          @provider.V4ToolInputDelta(
            id=call_id,
            delta=arguments,
            provider_metadata~,
          ),
        )
      }
      events.push(@provider.V4ToolInputEnd(id=call_id, provider_metadata~))
      events.push(
        @provider.V4ToolCallReady({
          tool_call_id: call_id,
          tool_name: name,
          input: arguments,
          provider_executed: false,
          dynamic: false,
          provider_metadata,
        }),
      )
    }
    _ => ()
  }
}

///|
fn PerplexityAgentStreamDecoder::emit_output_item(
  self : PerplexityAgentStreamDecoder,
  item : Json,
  output_index : Int32?,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  match item {
    { "type": "message", "content": Array(parts), .. } =>
      for content_index, part in parts {
        if part is { "type": "output_text", .. } {
          let id = perplexity_agent_text_id(
            @provider_utils.json_string_field(item, "id"),
            output_index,
            Some(content_index),
          )
          self.finish_text(
            id,
            @provider_utils.json_string_field(part, "text"),
            events,
          )
        }
        self.emit_annotations(part, events)
      }
    { "type": "search_results", .. } => {
      for query in perplexity_agent_search_queries(item) {
        if !self.search_queries.contains(query) {
          self.search_queries.push(query)
        }
      }
      match item {
        { "results": Array(results), .. } =>
          for result in results {
            match
              perplexity_agent_search_result_source(result, self.id_generator) {
              Some(@provider.V4SourceOutput(source)) =>
                self.emit_source(source, events)
              _ => ()
            }
          }
        _ => ()
      }
    }
    { "type": "fetch_url_results", "contents": Array(contents), .. } =>
      for value in contents {
        match perplexity_agent_fetch_result_source(value, self.id_generator) {
          Some(@provider.V4SourceOutput(source)) =>
            self.emit_source(source, events)
          _ => ()
        }
      }
    { "type": "function_call", .. } => self.emit_function_call(item, events)
    _ => ()
  }
}

///|
fn PerplexityAgentStreamDecoder::emit_reasoning_thought(
  self : PerplexityAgentStreamDecoder,
  json : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  match @provider_utils.json_string_field(json, "thought") {
    Some(text) if text != "" =>
      match self.active_reasoning_id {
        Some(id) =>
          events.push(
            @provider.V4ReasoningDelta(
              id~,
              delta=text,
              provider_metadata=Map([]),
            ),
          )
        None => ()
      }
    _ => ()
  }
}

///|
fn PerplexityAgentStreamDecoder::start_reasoning(
  self : PerplexityAgentStreamDecoder,
  json : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.active_reasoning_id is Some(id) {
    events.push(@provider.V4ReasoningEnd(id~, provider_metadata=Map([])))
  }
  let suffix = match
    @provider_utils.json_int_field_opt(json, "sequence_number") {
    Some(sequence_number) => sequence_number.to_string()
    None => (self.id_generator)()
  }
  let id = "reasoning-" + suffix
  self.active_reasoning_id = Some(id)
  events.push(@provider.V4ReasoningStart(id~, provider_metadata=Map([])))
  self.emit_reasoning_thought(json, events)
}

///|
fn PerplexityAgentStreamDecoder::process_reasoning_results(
  self : PerplexityAgentStreamDecoder,
  json : Json,
  field : String,
  source_kind : String,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  self.emit_reasoning_thought(json, events)
  match json {
    { "results": Array(results), .. } if source_kind == "search" =>
      for result in results {
        match perplexity_agent_search_result_source(result, self.id_generator) {
          Some(@provider.V4SourceOutput(source)) =>
            self.emit_source(source, events)
          _ => ()
        }
      }
    { "contents": Array(results), .. } if source_kind == "fetch" =>
      for result in results {
        match perplexity_agent_fetch_result_source(result, self.id_generator) {
          Some(@provider.V4SourceOutput(source)) =>
            self.emit_source(source, events)
          _ => ()
        }
      }
    _ => ()
  }
  if field == "queries" {
    for query in perplexity_agent_search_queries(json) {
      if !self.search_queries.contains(query) {
        self.search_queries.push(query)
      }
    }
  }
}

///|
fn PerplexityAgentStreamDecoder::provider_metadata(
  self : PerplexityAgentStreamDecoder,
) -> Map[String, Json] {
  perplexity_agent_provider_metadata(self.usage, self.search_queries)
}

///|
fn PerplexityAgentStreamDecoder::final_events(
  self : PerplexityAgentStreamDecoder,
) -> Array[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  for index, id in self.text_ids {
    if !self.text_ended[index] {
      self.text_ended[index] = true
      events.push(@provider.V4TextEnd(id~, provider_metadata=Map([])))
    }
  }
  if self.active_reasoning_id is Some(id) {
    events.push(@provider.V4ReasoningEnd(id~, provider_metadata=Map([])))
    self.active_reasoning_id = None
  }
  self.flush_sources(events)
  events.push(
    @provider.V4Finish(
      usage=perplexity_agent_usage(self.usage),
      reason=self.finish_reason,
      provider_metadata=self.provider_metadata(),
    ),
  )
  events
}

///|
fn PerplexityAgentStreamDecoder::finish_reason_from_response(
  self : PerplexityAgentStreamDecoder,
  response : Json,
) -> Unit {
  let status = @provider_utils.json_string_field(response, "status").unwrap_or(
    "",
  )
  let reason = match response {
    { "incomplete_details": { "reason": String(value), .. }, .. } => Some(value)
    _ => None
  }
  let has_function_call = self.function_call_ids.length() > 0
  self.finish_reason = perplexity_map_agent_finish_reason(
    status, reason, has_function_call,
  )
}

///|
fn PerplexityAgentStreamDecoder::process_terminal_response(
  self : PerplexityAgentStreamDecoder,
  response : Json,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  self.response_metadata_from(response, events)
  self.usage = match response {
    { "usage": value, .. } if !(value is Null) => Some(value)
    _ => None
  }
  match response {
    { "output": Array(items), .. } =>
      for output_index, item in items {
        self.emit_output_item(item, Some(output_index), events)
      }
    _ => ()
  }
  self.finish_reason_from_response(response)
}

///|
fn PerplexityAgentStreamDecoder::decode_data(
  self : PerplexityAgentStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  if data.trim() == "[DONE]" {
    if self.finish_reason.unified == @provider.V4FinishOther {
      self.finish_reason = {
        unified: @provider.V4FinishOther,
        raw: Some("interrupted"),
      }
    }
    return { events: self.final_events(), consumed_event: true, done: true, }
  }
  let json = @json.parse(data) catch {
    _ => {
      self.finish_reason = { unified: @provider.V4FinishError, raw: None, }
      let events : Array[@provider.LanguageModelV4StreamPart] = []
      if self.include_raw_chunks {
        events.push(@provider.V4Raw(Json::string(data)))
      }
      events.push(
        @provider.V4Error(
          @provider.StreamErrorInfo::new(
            "Perplexity Agent API stream returned invalid JSON",
            data=Json::string(data),
          ),
        ),
      )
      return { events, consumed_event: true, done: false, }
    }
  }
  guard json is Object(_) else {
    self.finish_reason = { unified: @provider.V4FinishError, raw: None, }
    let events : Array[@provider.LanguageModelV4StreamPart] = []
    if self.include_raw_chunks {
      events.push(@provider.V4Raw(json))
    }
    events.push(
      @provider.V4Error(
        @provider.StreamErrorInfo::new(
          "Perplexity Agent API chunk is not an object",
          data=json,
        ),
      ),
    )
    return { events, consumed_event: true, done: false, }
  }
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.include_raw_chunks {
    events.push(@provider.V4Raw(json))
  }
  if perplexity_agent_chunk_validation_error(json) is Some(error) {
    self.finish_reason = { unified: @provider.V4FinishError, raw: None, }
    events.push(
      @provider.V4Error(
        @provider.StreamErrorInfo::new(
          "Invalid Perplexity Agent API stream chunk: " + error,
          data=json,
        ),
      ),
    )
    return { events, consumed_event: true, done: false, }
  }
  let kind = @provider_utils.json_string_field(json, "type").unwrap_or("")
  match kind {
    "response.created" | "response.in_progress" =>
      match json {
        { "response": Object(_) as response, .. } =>
          self.response_metadata_from(response, events)
        _ => ()
      }
    "response.output_text.delta" =>
      self.emit_text_delta(
        perplexity_agent_text_id(
          @provider_utils.json_string_field(json, "item_id"),
          @provider_utils.json_int_field_opt(json, "output_index"),
          @provider_utils.json_int_field_opt(json, "content_index"),
        ),
        @provider_utils.json_string_field(json, "delta").unwrap_or(""),
        events,
      )
    "response.output_text.done" =>
      self.finish_text(
        perplexity_agent_text_id(
          @provider_utils.json_string_field(json, "item_id"),
          @provider_utils.json_int_field_opt(json, "output_index"),
          @provider_utils.json_int_field_opt(json, "content_index"),
        ),
        @provider_utils.json_string_field(json, "text"),
        events,
      )
    "response.reasoning.started" => self.start_reasoning(json, events)
    "response.reasoning.search_queries" =>
      self.process_reasoning_results(json, "queries", "", events)
    "response.reasoning.fetch_url_queries" =>
      self.emit_reasoning_thought(json, events)
    "response.reasoning.search_results" =>
      self.process_reasoning_results(json, "", "search", events)
    "response.reasoning.fetch_url_results" =>
      self.process_reasoning_results(json, "", "fetch", events)
    "response.reasoning.stopped" => {
      self.emit_reasoning_thought(json, events)
      if self.active_reasoning_id is Some(id) {
        events.push(@provider.V4ReasoningEnd(id~, provider_metadata=Map([])))
        self.active_reasoning_id = None
      }
    }
    "response.output_item.done" =>
      match json {
        { "item": item, .. } =>
          self.emit_output_item(
            item,
            @provider_utils.json_int_field_opt(json, "output_index"),
            events,
          )
        _ => ()
      }
    "response.completed" | "response.incomplete" =>
      match json {
        { "response": Object(_) as response, .. } => {
          self.process_terminal_response(response, events)
          for event in self.final_events() {
            events.push(event)
          }
        }
        _ => {
          self.finish_reason = @provider.LanguageModelV4FinishReason::unknown()
          for event in self.final_events() {
            events.push(event)
          }
        }
      }
    "response.failed" | "error" => {
      let error = match json {
        { "error": { "message": String(message), .. }, .. } => message
        _ => "Perplexity response failed"
      }
      self.finish_reason = {
        unified: @provider.V4FinishError,
        raw: Some("failed"),
      }
      events.push(
        @provider.V4Error(@provider.StreamErrorInfo::new(error, data=json)),
      )
      for event in self.final_events() {
        events.push(event)
      }
    }
    _ => ()
  }
  { events, consumed_event: true, done: self.finalized, }
}

///|
fn PerplexityAgentStreamDecoder::feed_line(
  self : PerplexityAgentStreamDecoder,
  line : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  match self.sse.feed_line(line) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
fn PerplexityAgentStreamDecoder::flush_buffered(
  self : PerplexityAgentStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
fn PerplexityAgentStreamDecoder::finish_stream(
  self : PerplexityAgentStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  if self.finalized {
    @provider_utils.SseDecodeBatch::empty(true)
  } else {
    if self.finish_reason.unified == @provider.V4FinishOther {
      self.finish_reason = {
        unified: @provider.V4FinishOther,
        raw: Some("interrupted"),
      }
    }
    { events: self.final_events(), consumed_event: false, done: true, }
  }
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = self.prepare_agent_request(options)
  let body_fields : Map[String, Json] = Map([])
  match prepared.body {
    Object(fields) =>
      for entry in fields.iter2() {
        body_fields[entry.0] = entry.1
      }
    _ => ()
  }
  body_fields["stream"] = Json::boolean(true)
  let body = Json::object(body_fields)
  let decoder = PerplexityAgentStreamDecoder::new(
    options.include_raw_chunks,
    self.id_generator,
  )
  let url = @provider_utils.append_path(self.base_url, "/v1/agent")
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url~,
    headers=perplexity_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body~,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="Perplexity Agent API terminal response",
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=perplexity_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    start_events=[
      @provider.V4StreamStart(
        warnings=@provider.copy_warnings(prepared.warnings),
      ),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=line => decoder.feed_line(line),
    flush_buffered=() => decoder.flush_buffered(),
    finish_stream=() => decoder.finish_stream(),
    response=() => {
      decoder.response_metadata.unwrap_or(@provider.ResponseMetadata::empty())
    },
    transport=self.http_transport,
    on_event~,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(@provider.merge_response_metadata(Some(result.value), result.response)),
  )
}

///|
pub extend PerplexityLanguageModel with @QuietlyChan/moonai/provider.LanguageModelV4::{
  do_generate,
  specification_version,
  provider,
  supported_urls,
  do_stream,
  model_id,
}

///|
/// Stateful decoder for the Anthropic Messages API event stream.
pub struct AnthropicStreamDecoder {
  priv sse : @provider_utils.EventSourceBuffer
  priv include_raw_chunks : Bool
  priv text : StringBuilder
  priv reasoning : StringBuilder
  priv mut input_tokens : Int
  priv mut output_tokens : Int
  priv mut cache_creation_input_tokens : Int
  priv mut cache_read_input_tokens : Int
  priv mut reasoning_tokens : Int
  priv mut finish_reason : @provider.FinishReason
  priv block_kinds : Array[String]
  priv block_ids : Array[String]
  priv block_names : Array[String]
  priv block_signatures : Array[String]
  priv block_redacted_data : Array[String]
  priv block_data : Array[StringBuilder]
  priv block_started : Array[Bool]
  priv block_stopped : Array[Bool]
  priv block_ready : Array[Bool]
  priv block_tool_calls : Array[@provider.ToolCall?]
  priv block_tool_results : Array[@provider.ToolResult?]
  priv block_custom : Array[@provider.GeneratedCustomContent?]
  priv block_provider_executed : Array[Bool]
  priv block_dynamic : Array[Bool]
  priv block_tool_metadata : Array[Map[String, Json]]
  priv sources : Array[@provider.GeneratedSource]
  priv source_block_indices : Array[Int]
  priv mut source_index : Int
  priv tool_calls : Array[@provider.ToolCall]
  priv tool_results : Array[@provider.ToolResult]
  priv mcp_tool_names : Map[String, String]
  priv mcp_tool_metadata : Map[String, Map[String, Json]]
  priv provider_name : String
  priv generate_id : @provider_utils.IdGenerator
  priv tool_name_mapping : @provider_utils.ToolNameMapping
  priv mut response_metadata : @provider.ResponseMetadata?
  priv mut metadata_emitted : Bool
  priv mut provider_metadata : Map[String, Json]
  priv mut raw_usage : Json?
  priv mut finish_reason_raw : String?
  priv mut finalized : Bool
}

///|
/// Create an empty Anthropic SSE decoder.
pub fn AnthropicStreamDecoder::new(
  include_raw_chunks? : Bool = false,
  provider_name? : String = "",
  tool_name_mapping? : @provider_utils.ToolNameMapping,
  id_generator? : @provider_utils.IdGenerator,
) -> AnthropicStreamDecoder {
  {
    sse: @provider_utils.EventSourceBuffer::new(),
    include_raw_chunks,
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    input_tokens: 0,
    output_tokens: 0,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    reasoning_tokens: 0,
    finish_reason: @provider.Unknown(""),
    block_kinds: [],
    block_ids: [],
    block_names: [],
    block_signatures: [],
    block_redacted_data: [],
    block_data: [],
    block_started: [],
    block_stopped: [],
    block_ready: [],
    block_tool_calls: [],
    block_tool_results: [],
    block_custom: [],
    block_provider_executed: [],
    block_dynamic: [],
    block_tool_metadata: [],
    sources: [],
    source_block_indices: [],
    source_index: 0,
    tool_calls: [],
    tool_results: [],
    mcp_tool_names: Map([]),
    mcp_tool_metadata: Map([]),
    provider_name,
    generate_id: id_generator.unwrap_or(@provider_utils.generate_id),
    tool_name_mapping: tool_name_mapping.unwrap_or(
      @provider_utils.ToolNameMapping::identity(),
    ),
    response_metadata: None,
    metadata_emitted: false,
    provider_metadata: Map([]),
    raw_usage: None,
    finish_reason_raw: None,
    finalized: false,
  }
}

///|
/// Namespace used for Anthropic provider metadata attached to normalized
/// content. Endpoint-specific names are retained when supplied by a model.
fn anthropic_metadata_key(provider_name : String) -> String {
  if provider_name == "" {
    "anthropic"
  } else {
    provider_name
  }
}

///|
/// Map an Anthropic citation into the provider-neutral source representation.
/// Unknown citation variants remain available through raw chunks but are not
/// guessed into a misleading source type.
fn anthropic_citation_source(
  citation : Json,
  provider_name : String,
  source_id : String,
) -> @provider.GeneratedSource? {
  match citation {
    { "type": "web_search_result_location", "url": String(url), .. } => {
      let title = @provider_utils.json_string_field(citation, "title")
      let fields : Map[String, Json] = Map([])
      match @provider_utils.json_string_field(citation, "cited_text") {
        Some(value) => fields["citedText"] = Json::string(value)
        None => ()
      }
      match @provider_utils.json_string_field(citation, "encrypted_index") {
        Some(value) => fields["encryptedIndex"] = Json::string(value)
        None => ()
      }
      let metadata = anthropic_metadata_map(provider_name, Json::object(fields))
      Some(
        @provider.GeneratedSource::GeneratedUrlSource(
          id=source_id,
          url~,
          title~,
          provider_metadata=metadata,
        ),
      )
    }
    { "type": "page_location", "document_index": Number(_, ..), .. } => {
      let title = @provider_utils.json_string_field(citation, "document_title").unwrap_or(
        "Anthropic document",
      )
      let fields : Map[String, Json] = Map([])
      match @provider_utils.json_string_field(citation, "cited_text") {
        Some(value) => fields["citedText"] = Json::string(value)
        None => ()
      }
      match @provider_utils.json_int_field_opt(citation, "start_page_number") {
        Some(value) =>
          fields["startPageNumber"] = Json::number(value.to_double())
        None => ()
      }
      match @provider_utils.json_int_field_opt(citation, "end_page_number") {
        Some(value) => fields["endPageNumber"] = Json::number(value.to_double())
        None => ()
      }
      Some(
        @provider.GeneratedSource::GeneratedDocumentSource(
          id=source_id,
          media_type=@provider_utils.json_string_field(citation, "media_type").unwrap_or(
            "text/plain",
          ),
          title~,
          filename=@provider_utils.json_string_field(citation, "filename"),
          provider_metadata=anthropic_metadata_map(
            provider_name,
            Json::object(fields),
          ),
        ),
      )
    }
    { "type": "char_location", "document_index": Number(_, ..), .. } => {
      let title = @provider_utils.json_string_field(citation, "document_title").unwrap_or(
        "Anthropic document",
      )
      let fields : Map[String, Json] = Map([])
      match @provider_utils.json_string_field(citation, "cited_text") {
        Some(value) => fields["citedText"] = Json::string(value)
        None => ()
      }
      match @provider_utils.json_int_field_opt(citation, "start_char_index") {
        Some(value) =>
          fields["startCharIndex"] = Json::number(value.to_double())
        None => ()
      }
      match @provider_utils.json_int_field_opt(citation, "end_char_index") {
        Some(value) => fields["endCharIndex"] = Json::number(value.to_double())
        None => ()
      }
      Some(
        @provider.GeneratedSource::GeneratedDocumentSource(
          id=source_id,
          media_type=@provider_utils.json_string_field(citation, "media_type").unwrap_or(
            "text/plain",
          ),
          title~,
          filename=@provider_utils.json_string_field(citation, "filename"),
          provider_metadata=anthropic_metadata_map(
            provider_name,
            Json::object(fields),
          ),
        ),
      )
    }
    _ => None
  }
}

///|
/// Append all recognized citations from a text block and return their source
/// events. Citation deltas use the same shape as non-streaming citation data.
fn AnthropicStreamDecoder::append_anthropic_citations(
  self : AnthropicStreamDecoder,
  block_index : Int,
  citations : Array[Json],
  events : Array[@provider.StreamEvent],
) -> Unit {
  for citation in citations {
    let generated = (self.generate_id)()
    let source_id = if generated == "" {
      "anthropic-source-" + self.source_index.to_string()
    } else {
      generated
    }
    self.source_index = self.source_index + 1
    match anthropic_citation_source(citation, self.provider_name, source_id) {
      Some(source) => {
        self.sources.push(source)
        self.source_block_indices.push(block_index)
        events.push(@provider.SourceReady(source))
      }
      None => ()
    }
  }
}

///|
/// Retain identity and provider-specific fields carried by stream chunks.
fn AnthropicStreamDecoder::record_json(
  self : AnthropicStreamDecoder,
  json : Json,
) -> Unit {
  let chunk_metadata = @provider.ResponseMetadata::from_json(json)
  if !chunk_metadata.is_empty() {
    self.response_metadata = Some(
      @provider.merge_response_metadata(self.response_metadata, chunk_metadata),
    )
  }
  if self.provider_name != "" {
    self.provider_metadata = @provider.merge_provider_metadata(
      self.provider_metadata,
      @provider_utils.provider_metadata_from_json(json, self.provider_name),
    )
  }
  self.provider_metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    anthropic_response_provider_metadata(json, self.provider_name),
  )
  match json {
    { "message": Object(message), .. } =>
      self.record_json(Json::object(message))
    _ => ()
  }
}

///|
fn AnthropicStreamDecoder::ensure_block(
  self : AnthropicStreamDecoder,
  index : Int,
  data : Json,
) -> Unit raise {
  guard index >= 0 else {
    raise @provider.InvalidResponseDataError(
      message="Anthropic content block index must be non-negative",
      data~,
    )
  }
  while self.block_kinds.length() <= index {
    self.block_kinds.push("")
    self.block_ids.push("")
    self.block_names.push("")
    self.block_signatures.push("")
    self.block_redacted_data.push("")
    self.block_data.push(StringBuilder::new())
    self.block_started.push(false)
    self.block_stopped.push(false)
    self.block_ready.push(false)
    self.block_tool_calls.push(None)
    self.block_tool_results.push(None)
    self.block_custom.push(None)
    self.block_provider_executed.push(false)
    self.block_dynamic.push(false)
    self.block_tool_metadata.push(Map([]))
  }
}

///|
fn AnthropicStreamDecoder::block_id(
  self : AnthropicStreamDecoder,
  index : Int,
  kind : String,
) -> String {
  if self.block_ids[index] != "" {
    self.block_ids[index]
  } else if kind == "tool" {
    let generated = (self.generate_id)()
    let id = if generated == "" { "tool-{index}" } else { generated }
    self.block_ids[index] = id
    id
  } else {
    "\{kind}-\{index}"
  }
}

///|
fn AnthropicStreamDecoder::start_text_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if !self.block_started[index] {
    self.block_started[index] = true
    events.push(@provider.TextStart(self.block_id(index, "text")))
  }
}

///|
fn AnthropicStreamDecoder::start_reasoning_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if !self.block_started[index] {
    self.block_started[index] = true
    events.push(@provider.ReasoningStart(self.block_id(index, "reasoning")))
  }
}

///|
fn AnthropicStreamDecoder::start_tool_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  if !self.block_started[index] {
    self.block_started[index] = true
    let id = self.block_id(index, "tool")
    let name = if self.block_names[index] == "" {
      "tool-\{index}"
    } else {
      self.block_names[index]
    }
    events.push(@provider.ToolInputStart(id~, tool_name=name))
  }
}

///|
fn anthropic_server_tool_name(name : String) -> String {
  if name == "text_editor_code_execution" || name == "bash_code_execution" {
    "code_execution"
  } else {
    name
  }
}

///|
/// Normalize the few server-tool input shapes that AI SDK exposes as a
/// provider-executed tool call. The original payload is otherwise preserved.
fn anthropic_server_tool_input(name : String, input : Json) -> Json {
  if name == "text_editor_code_execution" || name == "bash_code_execution" {
    match input {
      Object(fields) => {
        let result = @provider.copy_provider_metadata(fields)
        result["type"] = Json::string(name)
        Json::object(result)
      }
      _ => input
    }
  } else if name == "code_execution" {
    match input {
      Object(fields) if fields.get("code") is Some(_) &&
        fields.get("type") is None => {
        let result = @provider.copy_provider_metadata(fields)
        result["type"] = Json::string("programmatic-tool-call")
        Json::object(result)
      }
      _ => input
    }
  } else {
    input
  }
}

///|
fn anthropic_tool_provider_metadata(
  provider_name : String,
  kind : String,
  server_name : String?,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([("type", Json::string(kind))])
  match server_name {
    Some(value) => fields["serverName"] = Json::string(value)
    None => ()
  }
  anthropic_metadata_map(provider_name, Json::object(fields))
}

///|
fn anthropic_tool_result_name(
  kind : String,
  tool_use_id : String,
  mcp_tool_names : Map[String, String],
) -> String {
  match kind {
    "mcp_tool_result" => mcp_tool_names.get(tool_use_id).unwrap_or("mcp_tool")
    "web_fetch_tool_result" => "web_fetch"
    "web_search_tool_result" => "web_search"
    "code_execution_tool_result"
    | "bash_code_execution_tool_result"
    | "text_editor_code_execution_tool_result" => "code_execution"
    "tool_search_tool_result" => "tool_search_tool"
    "advisor_tool_result" => "advisor"
    _ => kind
  }
}

///|
/// Convert a provider-executed result block into the normalized ToolResult
/// shape. Keeping the result payload untouched is important because each
/// Anthropic server tool has its own nested schema.
fn anthropic_tool_result_from_block(
  block : Json,
  provider_name : String,
  mcp_tool_names : Map[String, String],
  mcp_tool_metadata : Map[String, Map[String, Json]],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> @provider.ToolResult? {
  let kind = @provider_utils.json_string_field(block, "type").unwrap_or("")
  let tool_use_id = @provider_utils.json_string_field(block, "tool_use_id").unwrap_or(
    @provider_utils.json_string_field(block, "toolUseId").unwrap_or(""),
  )
  guard tool_use_id != "" else { return None }
  let result = anthropic_response_field(block, ["content", "result"]).unwrap_or(
    Json::empty_object(),
  )
  let is_error = match
    anthropic_response_field(block, ["is_error", "isError"]) {
    Some(True) => true
    _ =>
      match result {
        { "type": String(result_type), .. } =>
          result_type.contains("error") || result_type.contains("failure")
        _ => false
      }
  }
  let metadata = match kind {
    "mcp_tool_result" =>
      mcp_tool_metadata
      .get(tool_use_id)
      .unwrap_or(
        anthropic_tool_provider_metadata(provider_name, "mcp-tool-use", None),
      )
    _ => Map([])
  }
  Some(
    @provider.ToolResult::new(
      tool_call_id=tool_use_id,
      tool_name=tool_name_mapping.to_custom_tool_name(
        anthropic_tool_result_name(kind, tool_use_id, mcp_tool_names),
      ),
      result~,
      is_error~,
      dynamic=kind == "mcp_tool_result",
      provider_metadata=metadata,
    ),
  )
}

///|
fn anthropic_is_tool_call_kind(kind : String) -> Bool {
  kind == "tool_use" || kind == "server_tool_use" || kind == "mcp_tool_use"
}

///|
fn anthropic_is_tool_result_kind(kind : String) -> Bool {
  kind == "tool_result" ||
  kind == "web_fetch_tool_result" ||
  kind == "web_search_tool_result" ||
  kind == "code_execution_tool_result" ||
  kind == "bash_code_execution_tool_result" ||
  kind == "text_editor_code_execution_tool_result" ||
  kind == "tool_search_tool_result" ||
  kind == "advisor_tool_result" ||
  kind == "mcp_tool_result"
}

///|
/// Preserve an Anthropic block that has no provider-neutral representation.
/// The raw payload is intentionally nested under the provider namespace so
/// callers can round-trip newer API features without coupling `provider` to
/// every Anthropic content type.
fn anthropic_custom_block(
  kind : String,
  block : Json,
  provider_name : String,
) -> @provider.GeneratedCustomContent {
  @provider.GeneratedCustomContent::new(
    kind~,
    provider_metadata=anthropic_metadata_map(provider_name, {
      "type": kind,
      "raw": block,
    }),
  )
}

///|
fn AnthropicStreamDecoder::finish_tool_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit raise {
  if self.block_ready[index] {
    return
  }
  let id = self.block_id(index, "tool")
  let name = if self.block_names[index] == "" {
    "tool-\{index}"
  } else {
    self.block_names[index]
  }
  let raw = self.block_data[index].to_string()
  let arguments = if raw.trim().is_empty() { "{}" } else { raw }
  let parsed = @json.parse(arguments) catch {
    error =>
      raise @provider.InvalidResponseDataError(
        message="Anthropic tool call \'{name}\' has invalid JSON input: \{error}",
        data=Json::string(arguments),
      )
  }
  guard parsed is Object(_) else {
    raise @provider.InvalidResponseDataError(
      message="Anthropic tool call \'{name}\' input must be a JSON object",
      data=parsed,
    )
  }
  let call = @provider.ToolCall::new(
    id~,
    name~,
    arguments~,
    provider_executed=self.block_provider_executed[index],
    dynamic=self.block_dynamic[index],
    provider_metadata=self.block_tool_metadata[index],
  )
  self.tool_calls.push(call)
  self.block_tool_calls[index] = Some(call)
  self.block_ready[index] = true
  events.push(@provider.ToolCallReady(call))
}

///|
fn AnthropicStreamDecoder::finish_block(
  self : AnthropicStreamDecoder,
  index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit raise {
  if self.block_stopped[index] {
    return
  }
  let kind = self.block_kinds[index]
  if kind == "text" {
    if self.block_started[index] {
      events.push(@provider.TextEnd(self.block_id(index, "text")))
    }
  } else if kind == "thinking" || kind == "redacted_thinking" {
    if self.block_started[index] {
      events.push(@provider.ReasoningEnd(self.block_id(index, "reasoning")))
    }
  } else if kind == "compaction" {
    if !self.block_started[index] {
      self.start_text_block(index, events)
    }
    events.push(@provider.TextEnd(self.block_id(index, "text")))
  } else if anthropic_is_tool_call_kind(kind) {
    if !self.block_started[index] {
      self.start_tool_block(index, events)
    }
    events.push(@provider.ToolInputEnd(self.block_id(index, "tool")))
    self.finish_tool_block(index, events)
  } else if anthropic_is_tool_result_kind(kind) {
    match self.block_tool_results[index] {
      Some(result) => {
        events.push(@provider.ToolResultReady(result))
        self.block_ready[index] = true
      }
      None => ()
    }
  }
  self.block_stopped[index] = true
}

///|
fn AnthropicStreamDecoder::apply_usage(
  self : AnthropicStreamDecoder,
  usage : Json,
) -> Unit {
  self.raw_usage = Some(
    match self.raw_usage {
      Some(Object(previous)) => {
        let merged = @provider.copy_provider_metadata(previous)
        match usage {
          Object(current) =>
            for entry in current.iter2() {
              merged[entry.0] = entry.1
            }
          _ => ()
        }
        Json::object(merged)
      }
      _ => usage
    },
  )
  match self.raw_usage {
    Some(raw) =>
      self.provider_metadata = @provider.merge_provider_metadata(
        self.provider_metadata,
        anthropic_metadata_map(self.provider_name, { "usage": raw }),
      )
    None => ()
  }
  if @provider_utils.json_int_field_opt(usage, "input_tokens") is Some(value) {
    self.input_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "output_tokens") is Some(value) {
    self.output_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "cache_creation_input_tokens")
    is Some(value) {
    self.cache_creation_input_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "cache_read_input_tokens")
    is Some(value) {
    self.cache_read_input_tokens = value
  }
  if @provider_utils.json_int_field_opt(usage, "thinking_tokens") is Some(value) {
    self.reasoning_tokens = value
  } else if @provider_utils.json_int_field_opt(usage, "reasoning_tokens")
    is Some(value) {
    self.reasoning_tokens = value
  } else {
    match usage {
      {
        "output_tokens_details": { "thinking_tokens": Number(value, ..), .. },
        ..
      } => self.reasoning_tokens = value.to_int()
      _ => ()
    }
  }
  // Anthropic excludes compaction iterations from the top-level totals. AI
  // SDK sums executor iterations (but keeps advisor and fallback attribution
  // separate), so mirror that rule in the provider-neutral Usage value.
  let mut iteration_input = 0
  let mut iteration_output = 0
  let mut has_executor_iteration = false
  let mut served_by_fallback = false
  match usage {
    { "iterations": Array(iterations), .. } =>
      for iteration in iterations {
        let kind = @provider_utils.json_string_field(iteration, "type").unwrap_or(
          "",
        )
        if kind == "fallback_message" {
          served_by_fallback = true
        }
        if kind == "compaction" || kind == "message" {
          has_executor_iteration = true
          iteration_input = iteration_input +
            @provider_utils.json_int_field(iteration, "input_tokens")
          iteration_output = iteration_output +
            @provider_utils.json_int_field(iteration, "output_tokens")
        }
      }
    _ => ()
  }
  if has_executor_iteration && !served_by_fallback {
    self.input_tokens = iteration_input
    self.output_tokens = iteration_output
  }
}

///|
fn map_stop_reason(value : String) -> @provider.FinishReason {
  match value {
    "end_turn" | "stop_sequence" | "pause_turn" => @provider.Stop
    "tool_use" => @provider.ToolCalls
    "max_tokens" | "model_context_window_exceeded" => @provider.Length
    "refusal" => @provider.ContentFilter
    "error" => @provider.Error
    other => @provider.Unknown(other)
  }
}

///|
fn AnthropicStreamDecoder::usage(
  self : AnthropicStreamDecoder,
) -> @provider.Usage {
  let input = self.input_tokens +
    self.cache_creation_input_tokens +
    self.cache_read_input_tokens
  {
    input_tokens: input,
    output_tokens: self.output_tokens,
    total_tokens: input + self.output_tokens,
    reasoning_tokens: self.reasoning_tokens,
    cached_input_tokens: self.cache_read_input_tokens,
    cache_write_input_tokens: self.cache_creation_input_tokens,
  }
}

///|
fn AnthropicStreamDecoder::final_events(
  self : AnthropicStreamDecoder,
) -> Array[@provider.StreamEvent] raise {
  if self.finalized {
    return []
  }
  self.finalized = true
  let events : Array[@provider.StreamEvent] = []
  for index, kind in self.block_kinds {
    if anthropic_is_tool_call_kind(kind) &&
      self.finish_reason is @provider.Error {
      // Do not publish incomplete provider tool calls after an error frame.
      continue
    }
    self.finish_block(index, events)
    if anthropic_is_tool_result_kind(kind) &&
      self.block_tool_results[index] is Some(result) {
      // Result blocks may not receive a content_block_stop frame.
      if !self.block_ready[index] {
        events.push(@provider.ToolResultReady(result))
        self.block_ready[index] = true
      }
    }
  }
  let reason = match self.finish_reason {
    @provider.Unknown("") =>
      if self.tool_calls.length() > 0 {
        @provider.ToolCalls
      } else {
        @provider.Stop
      }
    other => other
  }
  self.finish_reason = reason
  events.push(@provider.Finish(usage=self.usage(), reason~))
  events
}

///|
fn AnthropicStreamDecoder::apply_json(
  self : AnthropicStreamDecoder,
  json : Json,
) -> (Array[@provider.StreamEvent], Bool) raise {
  let events : Array[@provider.StreamEvent] = []
  let event_type = @provider_utils.json_string_field(json, "type").unwrap_or("")
  match event_type {
    "message_start" => {
      let metadata = match json {
        { "message": message, .. } =>
          @provider.ResponseMetadata::from_json(message)
        _ => @provider.ResponseMetadata::empty()
      }
      if !metadata.is_empty() {
        self.response_metadata = Some(
          @provider.merge_response_metadata(self.response_metadata, metadata),
        )
      }
      if !self.metadata_emitted {
        self.metadata_emitted = true
        events.push(@provider.ResponseMetadataReady(metadata))
      }
      match json {
        { "message": { "usage": usage, "stop_reason": String(reason), .. }, .. } => {
          self.apply_usage(usage)
          self.finish_reason_raw = Some(reason)
          self.finish_reason = map_stop_reason(reason)
        }
        { "message": { "usage": usage, .. }, .. } => self.apply_usage(usage)
        { "message": { "stop_reason": String(reason), .. }, .. } => {
          self.finish_reason_raw = Some(reason)
          self.finish_reason = map_stop_reason(reason)
        }
        _ => ()
      }
      (events, false)
    }
    "content_block_start" => {
      match json {
        { "index": Number(index, ..), "content_block": Object(block), .. } => {
          let i = index.to_int()
          self.ensure_block(i, json)
          let kind = match block.get("type") {
            Some(String(value)) => value
            _ => ""
          }
          self.block_kinds[i] = kind
          if block.get("id") is Some(String(id)) {
            self.block_ids[i] = id
          }
          if block.get("name") is Some(String(name)) {
            self.block_names[i] = name
          }
          if block.get("signature") is Some(String(signature)) {
            self.block_signatures[i] = signature
          }
          if kind == "redacted_thinking" {
            match block.get("data") {
              Some(String(data)) => self.block_redacted_data[i] = data
              _ => ()
            }
          }
          if kind == "compaction" {
            match block.get("content") {
              Some(String(value)) => self.block_data[i].write_string(value)
              _ => ()
            }
          }
          if kind == "server_tool_use" {
            let original_name = self.block_names[i]
            self.block_names[i] = self.tool_name_mapping.to_custom_tool_name(
              anthropic_server_tool_name(original_name),
            )
            self.block_provider_executed[i] = true
            self.block_tool_metadata[i] = anthropic_tool_provider_metadata(
              self.provider_name,
              "server-tool-use",
              None,
            )
            match block.get("input") {
              Some(input) if input.stringify() != "{}" =>
                self.block_data[i].write_string(
                  anthropic_server_tool_input(original_name, input).stringify(),
                )
              _ => ()
            }
          } else if anthropic_is_tool_call_kind(kind) &&
            kind != "server_tool_use" {
            self.block_names[i] = self.tool_name_mapping.to_custom_tool_name(
              self.block_names[i],
            )
          }
          if kind == "mcp_tool_use" {
            self.block_provider_executed[i] = true
            self.block_dynamic[i] = true
            let server_name = match block.get("server_name") {
              Some(String(value)) => Some(value)
              _ => None
            }
            self.block_tool_metadata[i] = anthropic_tool_provider_metadata(
              self.provider_name,
              "mcp-tool-use",
              server_name,
            )
            let id = self.block_ids[i]
            let name = self.block_names[i]
            if id != "" {
              self.mcp_tool_names[id] = name
              self.mcp_tool_metadata[id] = self.block_tool_metadata[i]
            }
            match block.get("input") {
              Some(input) if input.stringify() != "{}" =>
                self.block_data[i].write_string(input.stringify())
              _ => ()
            }
          } else if anthropic_is_tool_call_kind(kind) &&
            kind != "server_tool_use" {
            match block.get("input") {
              Some(input) if input.stringify() != "{}" =>
                self.block_data[i].write_string(input.stringify())
              _ => ()
            }
          }
          if kind == "text" {
            self.start_text_block(i, events)
          } else if kind == "thinking" || kind == "redacted_thinking" {
            self.start_reasoning_block(i, events)
          } else if kind == "compaction" {
            self.start_text_block(i, events)
          } else if anthropic_is_tool_call_kind(kind) {
            self.start_tool_block(i, events)
          } else if anthropic_is_tool_result_kind(kind) {
            match
              anthropic_tool_result_from_block(
                Json::object(block),
                self.provider_name,
                self.mcp_tool_names,
                self.mcp_tool_metadata,
                self.tool_name_mapping,
              ) {
              Some(result) => {
                self.block_tool_results[i] = Some(result)
                self.tool_results.push(result)
              }
              None => ()
            }
          } else if kind != "" && kind != "fallback" {
            let custom = anthropic_custom_block(
              kind,
              Json::object(block),
              self.provider_name,
            )
            self.block_custom[i] = Some(custom)
            events.push(@provider.CustomContentReady(custom))
          }
        }
        _ => ()
      }
      (events, false)
    }
    "content_block_delta" => {
      match json {
        { "index": Number(index, ..), "delta": Object(delta), .. } => {
          let i = index.to_int()
          self.ensure_block(i, json)
          let delta_type = match delta.get("type") {
            Some(String(value)) => value
            _ => ""
          }
          if delta_type == "text_delta" {
            let value = match delta.get("text") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              if self.block_kinds[i] == "" {
                self.block_kinds[i] = "text"
              }
              self.start_text_block(i, events)
              self.text.write_string(value)
              self.block_data[i].write_string(value)
              events.push(
                @provider.TextDelta(id=self.block_id(i, "text"), delta=value),
              )
            }
          } else if delta_type == "thinking_delta" {
            let value = match delta.get("thinking") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              if self.block_kinds[i] == "" {
                self.block_kinds[i] = "thinking"
              }
              self.start_reasoning_block(i, events)
              self.reasoning.write_string(value)
              self.block_data[i].write_string(value)
              events.push(
                @provider.ReasoningDelta(
                  id=self.block_id(i, "reasoning"),
                  delta=value,
                ),
              )
            }
          } else if delta_type == "input_json_delta" {
            let value = match delta.get("partial_json") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              if self.block_kinds[i] == "" {
                self.block_kinds[i] = "tool_use"
              }
              self.start_tool_block(i, events)
              self.block_data[i].write_string(value)
              events.push(
                @provider.ToolInputDelta(
                  id=self.block_id(i, "tool"),
                  delta=value,
                ),
              )
            }
          } else if delta_type == "compaction_delta" {
            let value = match delta.get("content") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              self.block_kinds[i] = "compaction"
              self.start_text_block(i, events)
              self.block_data[i].write_string(value)
              events.push(
                @provider.TextDelta(id=self.block_id(i, "text"), delta=value),
              )
            }
          } else if delta_type == "signature_delta" {
            match delta.get("signature") {
              Some(String(signature)) =>
                self.block_signatures[i] = self.block_signatures[i] + signature
              _ => ()
            }
          } else if delta_type == "citations_delta" {
            match delta.get("citation") {
              Some(citation) =>
                self.append_anthropic_citations(i, [citation], events)
              None => ()
            }
          } else if delta_type != "signature_delta" && !self.include_raw_chunks {
            events.push(@provider.Raw(json))
          }
        }
        _ => ()
      }
      (events, false)
    }
    "content_block_stop" => {
      match json {
        { "index": Number(index, ..), .. } => {
          let i = index.to_int()
          self.ensure_block(i, json)
          self.finish_block(i, events)
        }
        _ => ()
      }
      (events, false)
    }
    "message_delta" => {
      match json {
        { "delta": Object(delta), "usage": usage, .. } => {
          self.apply_usage(usage)
          if delta.get("stop_reason") is Some(String(reason)) {
            self.finish_reason_raw = Some(reason)
            self.finish_reason = map_stop_reason(reason)
          }
        }
        { "delta": Object(delta), .. } =>
          if delta.get("stop_reason") is Some(String(reason)) {
            self.finish_reason_raw = Some(reason)
            self.finish_reason = map_stop_reason(reason)
          }
        { "usage": usage, .. } => self.apply_usage(usage)
        _ => ()
      }
      (events, false)
    }
    "message_stop" => (self.final_events(), true)
    "error" => {
      let message = match json {
        { "error": Object(error), .. } =>
          match error.get("message") {
            Some(String(value)) => value
            _ => json.stringify()
          }
        _ => json.stringify()
      }
      self.finish_reason_raw = Some("error")
      self.finish_reason = @provider.Error
      events.push(@provider.StreamError(message))
      let final_events = self.final_events()
      for event in final_events {
        events.push(event)
      }
      (events, true)
    }
    "ping" => (events, false)
    _ => {
      if !self.include_raw_chunks {
        events.push(@provider.Raw(json))
      }
      (events, false)
    }
  }
}

///|
fn AnthropicStreamDecoder::decode_data(
  self : AnthropicStreamDecoder,
  data : String,
) -> @provider_utils.DecodeBatch raise {
  if data.trim() == "[DONE]" {
    return { events: self.final_events(), consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error =>
      raise @provider.InvalidResponseDataError(
        message="Anthropic stream decode error: \{error}; data: \{data}",
        data=Json::string(data),
      )
  }
  self.record_json(json)
  let (events, done) = self.apply_json(json)
  if self.include_raw_chunks {
    let all_events : Array[@provider.StreamEvent] = [@provider.Raw(json)]
    for event in events {
      all_events.push(event)
    }
    { events: all_events, consumed_event: true, done }
  } else {
    { events, consumed_event: true, done }
  }
}

///|
/// Feed one physical SSE line. A blank line flushes the accumulated `data:`
/// payload; comments and other SSE fields are ignored.
pub fn AnthropicStreamDecoder::feed_line(
  self : AnthropicStreamDecoder,
  raw : String,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated `data:` event before reporting EOF.
pub fn AnthropicStreamDecoder::flush_buffered(
  self : AnthropicStreamDecoder,
) -> @provider_utils.DecodeBatch raise {
  match self.sse.flush() {
    Some(data) => self.decode_data(data)
    None => @provider_utils.DecodeBatch::empty(self.finalized)
  }
}

///|
/// Return the accumulated response after the stream reaches `message_stop`.
pub fn AnthropicStreamDecoder::response(
  self : AnthropicStreamDecoder,
) -> @provider.ChatResponse {
  let reason = match self.finish_reason {
    @provider.Unknown(value) if value == "" && self.tool_calls.length() > 0 =>
      @provider.ToolCalls
    other => other
  }
  let content : Array[@provider.GeneratedContent] = []
  for index, kind in self.block_kinds {
    if kind == "text" {
      let value = self.block_data[index].to_string()
      if value != "" {
        content.push(@provider.GeneratedContent::text(value))
      }
    } else if kind == "compaction" {
      content.push(
        @provider.GeneratedContent::text(
          self.block_data[index].to_string(),
          provider_metadata=anthropic_metadata_map(self.provider_name, {
            "type": "compaction",
          }),
        ),
      )
    } else if kind == "thinking" {
      let value = self.block_data[index].to_string()
      if value != "" || self.block_signatures[index] != "" {
        let metadata : Map[String, Json] = if self.block_signatures[index] != "" {
          anthropic_metadata_map(self.provider_name, {
            "signature": self.block_signatures[index],
          })
        } else {
          Map([])
        }
        content.push(
          @provider.GeneratedContent::reasoning(
            value,
            provider_metadata=metadata,
          ),
        )
      }
    } else if kind == "redacted_thinking" {
      let metadata : Map[String, Json] = anthropic_metadata_map(
        self.provider_name,
        { "redactedData": self.block_redacted_data[index] },
      )
      content.push(
        @provider.GeneratedContent::reasoning("", provider_metadata=metadata),
      )
    } else if anthropic_is_tool_call_kind(kind) &&
      self.block_tool_calls[index] is Some(call) {
      content.push(@provider.GeneratedContent::tool_call(call))
    } else if anthropic_is_tool_result_kind(kind) &&
      self.block_tool_results[index] is Some(result) {
      content.push(@provider.GeneratedContent::tool_result(result))
    } else if self.block_custom[index] is Some(custom) {
      content.push(@provider.GeneratedContent::GeneratedCustomOutput(custom))
    }
    for source_index, source_block_index in self.source_block_indices {
      if source_block_index == index {
        content.push(
          @provider.GeneratedContent::GeneratedSourceOutput(
            self.sources[source_index],
          ),
        )
      }
    }
  }
  @provider.ChatResponse::from_content(content, self.usage(), reason).with_diagnostics(
    None,
    self.response_metadata,
    self.provider_metadata,
    [],
  )
}

///|
/// Return lossless V4 usage accumulated from message_start/message_delta.
pub fn AnthropicStreamDecoder::v4_usage(
  self : AnthropicStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  anthropic_v4_usage_from_raw(self.raw_usage)
}

///|
/// Return the normalized and provider-native Anthropic stop reason.
pub fn AnthropicStreamDecoder::v4_finish_reason(
  self : AnthropicStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  anthropic_v4_finish_reason(self.finish_reason, self.finish_reason_raw)
}

///|
/// Snapshot provider metadata without exposing the decoder's mutable map.
pub fn AnthropicStreamDecoder::provider_metadata_snapshot(
  self : AnthropicStreamDecoder,
) -> Map[String, Json] {
  @provider.copy_provider_metadata(self.provider_metadata)
}

///|
fn anthropic_response_error(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn anthropic_usage_from_json(json : Json) -> @provider.Usage {
  let mut input_tokens = @provider_utils.json_int_field(json, "input_tokens")
  let mut output_tokens = @provider_utils.json_int_field(json, "output_tokens")
  let cache_creation = @provider_utils.json_int_field(
    json, "cache_creation_input_tokens",
  )
  let cache_read = @provider_utils.json_int_field(
    json, "cache_read_input_tokens",
  )
  let reasoning_tokens = match
    @provider_utils.json_int_field_opt(json, "thinking_tokens") {
    Some(value) => value
    None =>
      match @provider_utils.json_int_field_opt(json, "reasoning_tokens") {
        Some(value) => value
        None =>
          match json {
            {
              "output_tokens_details": {
                "thinking_tokens": Number(value, ..),
                ..
              },
              ..
            } => value.to_int()
            _ => 0
          }
      }
  }
  let mut iteration_input = 0
  let mut iteration_output = 0
  let mut has_executor_iteration = false
  let mut served_by_fallback = false
  match json {
    { "iterations": Array(iterations), .. } =>
      for iteration in iterations {
        let kind = @provider_utils.json_string_field(iteration, "type").unwrap_or(
          "",
        )
        if kind == "fallback_message" {
          served_by_fallback = true
        }
        if kind == "compaction" || kind == "message" {
          has_executor_iteration = true
          iteration_input = iteration_input +
            @provider_utils.json_int_field(iteration, "input_tokens")
          iteration_output = iteration_output +
            @provider_utils.json_int_field(iteration, "output_tokens")
        }
      }
    _ => ()
  }
  if has_executor_iteration && !served_by_fallback {
    input_tokens = iteration_input
    output_tokens = iteration_output
  }
  let input = input_tokens + cache_creation + cache_read
  {
    input_tokens: input,
    output_tokens,
    total_tokens: input + output_tokens,
    reasoning_tokens,
    cached_input_tokens: cache_read,
    cache_write_input_tokens: cache_creation,
  }
}

///|
fn anthropic_v4_reasoning_tokens(json : Json) -> Int? {
  match @provider_utils.json_int_field_opt(json, "thinking_tokens") {
    Some(value) => Some(value)
    None =>
      match @provider_utils.json_int_field_opt(json, "reasoning_tokens") {
        Some(value) => Some(value)
        None =>
          match json {
            {
              "output_tokens_details": {
                "thinking_tokens": Number(value, ..),
                ..
              },
              ..
            } => Some(value.to_int())
            _ => None
          }
      }
  }
}

///|
/// Preserve Anthropic's provider-native usage object while exposing the V4
/// cache and reasoning counters separately.
fn anthropic_v4_usage_from_raw(
  raw_usage : Json?,
) -> @provider.LanguageModelV4Usage {
  match raw_usage {
    Some(raw) if raw is Object(_) => {
      let normalized = anthropic_usage_from_json(raw)
      let cache_read = @provider_utils.json_int_field(
        raw, "cache_read_input_tokens",
      )
      let cache_write = @provider_utils.json_int_field(
        raw, "cache_creation_input_tokens",
      )
      let reasoning = anthropic_v4_reasoning_tokens(raw)
      {
        input_tokens: {
          total: Some(normalized.input_tokens),
          no_cache: Some(
            (normalized.input_tokens - cache_read - cache_write).max(0),
          ),
          cache_read: Some(cache_read),
          cache_write: Some(cache_write),
        },
        output_tokens: {
          total: Some(normalized.output_tokens),
          text: reasoning.map(value => (normalized.output_tokens - value).max(0)),
          reasoning,
        },
        raw: Some(raw),
      }
    }
    _ => @provider.LanguageModelV4Usage::unknown()
  }
}

///|
fn anthropic_response_usage_json(json : Json) -> Json? {
  match json {
    { "usage": usage, .. } => Some(usage)
    _ => None
  }
}

///|
fn anthropic_response_stop_reason(json : Json) -> String? {
  match json {
    { "stop_reason": String(value), .. } => Some(value)
    _ => None
  }
}

///|
fn anthropic_v4_finish_reason(
  reason : @provider.FinishReason,
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  @provider.LanguageModelV4FinishReason::from_finish_reason(reason).with_raw(
    raw,
  )
}

///|
/// Decode one non-streaming Anthropic Messages response.
pub fn decode_messages_response(
  json : Json,
  provider_name? : String = "anthropic.messages",
  tool_name_mapping? : @provider_utils.ToolNameMapping,
  id_generator? : @provider_utils.IdGenerator,
) -> @provider.ChatResponse raise {
  if anthropic_response_error(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="Anthropic request failed: \{message}",
      data=json,
    )
  }
  let content : Array[@provider.GeneratedContent] = []
  let generate_id = id_generator.unwrap_or(@provider_utils.generate_id)
  let mut has_tool_calls = false
  let mcp_tool_names : Map[String, String] = Map([])
  let mcp_tool_metadata : Map[String, Map[String, Json]] = Map([])
  let resolved_tool_name_mapping = tool_name_mapping.unwrap_or(
    @provider_utils.ToolNameMapping::identity(),
  )
  match json {
    { "content": Array(blocks), .. } =>
      for index, block in blocks {
        match block {
          {
            "type": "text",
            "text": String(value),
            "citations": Array(citations),
            ..
          } => {
            content.push(@provider.GeneratedContent::text(value))
            for citation_index, citation in citations {
              match
                anthropic_citation_source(
                  citation,
                  provider_name,
                  {
                    let generated = generate_id()
                    if generated == "" {
                      "anthropic-source-" +
                      index.to_string() +
                      "-" +
                      citation_index.to_string()
                    } else {
                      generated
                    }
                  },
                ) {
                Some(source) =>
                  content.push(
                    @provider.GeneratedContent::GeneratedSourceOutput(source),
                  )
                None => ()
              }
            }
          }
          { "type": "text", "text": String(value), .. } =>
            content.push(@provider.GeneratedContent::text(value))
          {
            "type": "thinking",
            "thinking": String(value),
            "signature": String(signature),
            ..
          } => {
            let metadata : Map[String, Json] = anthropic_metadata_map(
              provider_name,
              { "signature": signature },
            )
            content.push(
              @provider.GeneratedContent::reasoning(
                value,
                provider_metadata=metadata,
              ),
            )
          }
          { "type": "thinking", "thinking": String(value), .. } =>
            content.push(@provider.GeneratedContent::reasoning(value))
          { "type": "redacted_thinking", "data": String(data), .. } =>
            content.push(
              @provider.GeneratedContent::reasoning(
                "",
                provider_metadata=anthropic_metadata_map(provider_name, {
                  "redactedData": data,
                }),
              ),
            )
          { "type": "compaction", "content": String(value), .. } =>
            content.push(
              @provider.GeneratedContent::text(
                value,
                provider_metadata=anthropic_metadata_map(provider_name, {
                  "type": "compaction",
                }),
              ),
            )
          {
            "type": "tool_use",
            "id": String(id),
            "name": String(name),
            "input": input,
            ..
          } => {
            content.push(
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(
                  id~,
                  name=resolved_tool_name_mapping.to_custom_tool_name(name),
                  arguments=input.stringify(),
                ),
              ),
            )
            has_tool_calls = true
          }
          { "type": "tool_use", "name": String(name), "input": input, .. } => {
            content.push(
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(
                  id=generate_id(),
                  name=resolved_tool_name_mapping.to_custom_tool_name(name),
                  arguments=input.stringify(),
                ),
              ),
            )
            has_tool_calls = true
          }
          {
            "type": "server_tool_use",
            "id": String(id),
            "name": String(name),
            "input": input,
            ..
          } => {
            let normalized_name = anthropic_server_tool_name(name)
            let normalized_input = anthropic_server_tool_input(name, input)
            content.push(
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(
                  id~,
                  name=resolved_tool_name_mapping.to_custom_tool_name(
                    normalized_name,
                  ),
                  arguments=normalized_input.stringify(),
                  provider_executed=true,
                  provider_metadata=anthropic_tool_provider_metadata(
                    provider_name,
                    "server-tool-use",
                    None,
                  ),
                ),
              ),
            )
            has_tool_calls = true
          }
          {
            "type": "mcp_tool_use",
            "id": String(id),
            "name": String(name),
            "input": input,
            ..
          } => {
            let metadata = anthropic_tool_provider_metadata(
              provider_name,
              "mcp-tool-use",
              @provider_utils.json_string_field(block, "server_name"),
            )
            let custom_name = resolved_tool_name_mapping.to_custom_tool_name(
              name,
            )
            mcp_tool_names[id] = custom_name
            mcp_tool_metadata[id] = metadata
            content.push(
              @provider.GeneratedContent::tool_call(
                @provider.ToolCall::new(
                  id~,
                  name=custom_name,
                  arguments=input.stringify(),
                  provider_executed=true,
                  dynamic=true,
                  provider_metadata=metadata,
                ),
              ),
            )
            has_tool_calls = true
          }
          { "type": String(kind), .. } if anthropic_is_tool_result_kind(kind) =>
            match
              anthropic_tool_result_from_block(
                block, provider_name, mcp_tool_names, mcp_tool_metadata, resolved_tool_name_mapping,
              ) {
              Some(result) =>
                content.push(@provider.GeneratedContent::tool_result(result))
              None => ()
            }
          { "type": "fallback", .. } => ()
          { "type": String(kind), .. } if kind != "" =>
            content.push(
              @provider.GeneratedContent::GeneratedCustomOutput(
                anthropic_custom_block(kind, block, provider_name),
              ),
            )
          _ => ()
        }
      }
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Anthropic response has no content array",
        data=json,
      )
  }
  let usage = match json {
    { "usage": usage, .. } => anthropic_usage_from_json(usage)
    _ => @provider.Usage::zero()
  }
  let finish_reason = match json {
    { "stop_reason": String(reason), .. } => map_stop_reason(reason)
    _ => if has_tool_calls { @provider.ToolCalls } else { @provider.Stop }
  }
  let response_metadata = @provider.ResponseMetadata::from_json(json)
  let provider_metadata = @provider.merge_provider_metadata(
    @provider_utils.provider_metadata_from_json(json, provider_name),
    anthropic_response_provider_metadata(json, provider_name),
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

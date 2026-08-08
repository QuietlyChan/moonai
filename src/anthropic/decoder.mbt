///|
/// Stateful decoder for the Anthropic Messages API event stream.
priv struct AnthropicStreamDecoder {
  sse : @provider_utils.EventSourceBuffer
  include_raw_chunks : Bool
  text : StringBuilder
  reasoning : StringBuilder
  mut input_tokens : Int
  mut output_tokens : Int
  mut cache_creation_input_tokens : Int
  mut cache_read_input_tokens : Int
  mut reasoning_tokens : Int
  mut finish_reason : @provider.FinishReason
  block_kinds : Array[String]
  block_ids : Array[String]
  block_names : Array[String]
  block_signatures : Array[String]
  block_redacted_data : Array[String]
  block_citations : Array[Array[Json]]
  block_data : Array[StringBuilder]
  block_started : Array[Bool]
  block_stopped : Array[Bool]
  block_ready : Array[Bool]
  block_tool_calls : Array[@provider.ToolCall?]
  block_tool_results : Array[@provider.ToolResult?]
  block_custom : Array[@provider.GeneratedCustomContent?]
  block_provider_executed : Array[Bool]
  block_dynamic : Array[Bool]
  block_tool_metadata : Array[Map[String, Json]]
  sources : Array[@provider.GeneratedSource]
  source_block_indices : Array[Int]
  mut source_index : Int
  tool_calls : Array[@provider.ToolCall]
  tool_results : Array[@provider.ToolResult]
  server_tool_names : Map[String, String]
  mcp_tool_names : Map[String, String]
  mcp_tool_metadata : Map[String, Map[String, Json]]
  citation_documents : Array[AnthropicCitationDocument]
  provider_name : String
  canonical_metadata : Bool
  include_custom_provider_metadata : Bool
  mark_code_execution_dynamic : Bool
  uses_json_response_tool : Bool
  block_json_response_tools : Array[Bool]
  mut is_json_response_from_tool : Bool
  generate_id : @provider_utils.IdGenerator
  tool_name_mapping : @provider_utils.ToolNameMapping
  mut response_metadata : @provider.ResponseMetadata?
  mut received_data_event : Bool
  mut provider_metadata : Map[String, Json]
  mut raw_usage : Json?
  mut finish_reason_raw : String?
  mut message_finalized : Bool
  mut saw_message_stop : Bool
  mut message_had_tool_call : Bool
  mut finalized : Bool
}

///|
/// Create an Anthropic SSE decoder with an explicit metadata policy.
fn AnthropicStreamDecoder::new_with_metadata_policy(
  include_raw_chunks~ : Bool,
  provider_name~ : String,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
  mark_code_execution_dynamic~ : Bool,
  uses_json_response_tool~ : Bool,
  tool_name_mapping~ : @provider_utils.ToolNameMapping,
  id_generator~ : @provider_utils.IdGenerator,
  citation_documents~ : Array[AnthropicCitationDocument],
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
    block_citations: [],
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
    server_tool_names: Map([]),
    mcp_tool_names: Map([]),
    mcp_tool_metadata: Map([]),
    citation_documents: citation_documents.copy(),
    provider_name,
    canonical_metadata,
    include_custom_provider_metadata,
    mark_code_execution_dynamic,
    uses_json_response_tool,
    block_json_response_tools: [],
    is_json_response_from_tool: false,
    generate_id: id_generator,
    tool_name_mapping,
    response_metadata: None,
    received_data_event: false,
    provider_metadata: Map([]),
    raw_usage: None,
    finish_reason_raw: None,
    message_finalized: false,
    saw_message_stop: false,
    message_had_tool_call: false,
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
fn AnthropicStreamDecoder::metadata_map(
  self : AnthropicStreamDecoder,
  value : Json,
) -> Map[String, Json] {
  let metadata = anthropic_resolved_metadata_map(
    self.provider_name,
    value,
    self.canonical_metadata,
    self.include_custom_provider_metadata,
  )
  if self.canonical_metadata &&
    self.provider_metadata.get(self.provider_name) is Some(_) {
    match metadata.get("anthropic") {
      Some(value) => metadata[self.provider_name] = value
      None => ()
    }
  }
  metadata
}

///|
/// Map an Anthropic citation into the provider-neutral source representation.
/// Unknown citation variants remain available through raw chunks but are not
/// guessed into a misleading source type.
fn anthropic_citation_source(
  citation : Json,
  citation_documents : Array[AnthropicCitationDocument],
  provider_name : String,
  source_id : String,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
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
      let metadata = anthropic_resolved_metadata_map(
        provider_name,
        Json::object(fields),
        canonical_metadata,
        include_custom_provider_metadata,
      )
      Some(
        @provider.GeneratedSource::GeneratedUrlSource(
          id=source_id,
          url~,
          title~,
          provider_metadata=metadata,
        ),
      )
    }
    { "type": "page_location", "document_index": Number(index, ..), .. } => {
      let document_index = index.to_int()
      guard document_index >= 0 && document_index < citation_documents.length() else {
        return None
      }
      let document = citation_documents[document_index]
      let title = @provider_utils.json_string_field(citation, "document_title").unwrap_or(
        document.title,
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
          media_type=document.media_type,
          title~,
          filename=document.filename,
          provider_metadata=anthropic_resolved_metadata_map(
            provider_name,
            Json::object(fields),
            canonical_metadata,
            include_custom_provider_metadata,
          ),
        ),
      )
    }
    { "type": "char_location", "document_index": Number(index, ..), .. } => {
      let document_index = index.to_int()
      guard document_index >= 0 && document_index < citation_documents.length() else {
        return None
      }
      let document = citation_documents[document_index]
      let title = @provider_utils.json_string_field(citation, "document_title").unwrap_or(
        document.title,
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
          media_type=document.media_type,
          title~,
          filename=document.filename,
          provider_metadata=anthropic_resolved_metadata_map(
            provider_name,
            Json::object(fields),
            canonical_metadata,
            include_custom_provider_metadata,
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
    if @provider_utils.json_string_field(citation, "type")
      is Some("web_search_result_location") {
      self.block_citations[block_index].push(citation)
    }
    let generated = (self.generate_id)()
    let source_id = if generated == "" {
      "anthropic-source-" + self.source_index.to_string()
    } else {
      generated
    }
    self.source_index = self.source_index + 1
    match
      anthropic_citation_source(
        citation,
        self.citation_documents,
        self.provider_name,
        source_id,
        canonical_metadata=self.canonical_metadata,
        include_custom_provider_metadata=self.include_custom_provider_metadata,
      ) {
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
fn anthropic_web_search_sources(
  content : Json,
  provider_name : String,
  generate_id : @provider_utils.IdGenerator,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
) -> Array[@provider.GeneratedSource] {
  let sources : Array[@provider.GeneratedSource] = []
  match content {
    Array(results) =>
      for result in results {
        match @provider_utils.json_string_field(result, "url") {
          Some(url) => {
            let title = @provider_utils.json_string_field(result, "title").unwrap_or(
              url,
            )
            let generated = generate_id()
            let source_id = if generated == "" {
              "anthropic-search-source-{sources.length()}"
            } else {
              generated
            }
            let metadata = anthropic_resolved_metadata_map(
              provider_name,
              {
                "pageAge": anthropic_object_field(
                  result,
                  "page_age",
                  Json::null(),
                ),
              },
              canonical_metadata,
              include_custom_provider_metadata,
            )
            sources.push(
              @provider.GeneratedSource::GeneratedUrlSource(
                id=source_id,
                url~,
                title=Some(title),
                provider_metadata=metadata,
              ),
            )
          }
          None => ()
        }
      }
    _ => ()
  }
  sources
}

///|
fn AnthropicStreamDecoder::append_anthropic_web_search_sources(
  self : AnthropicStreamDecoder,
  block_index : Int,
  content : Json,
  events : Array[@provider.StreamEvent],
) -> Unit {
  for
    source in anthropic_web_search_sources(
      content,
      self.provider_name,
      self.generate_id,
      canonical_metadata=self.canonical_metadata,
      include_custom_provider_metadata=self.include_custom_provider_metadata,
    ) {
    self.sources.push(source)
    self.source_block_indices.push(block_index)
    events.push(@provider.SourceReady(source))
  }
}

///|
/// Retain identity and provider-specific fields carried by stream chunks.
fn AnthropicStreamDecoder::record_json(
  self : AnthropicStreamDecoder,
  json : Json,
) -> Unit {
  let chunk_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created_at"),
  )
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
  let response_provider_metadata = anthropic_response_provider_metadata(
    json,
    self.provider_name,
    canonical_metadata=self.canonical_metadata,
    include_custom_provider=self.include_custom_provider_metadata,
  )
  if self.canonical_metadata &&
    self.provider_metadata.get(self.provider_name) is Some(_) {
    match response_provider_metadata.get("anthropic") {
      Some(value) => response_provider_metadata[self.provider_name] = value
      None => ()
    }
  }
  self.provider_metadata = @provider.merge_provider_metadata(
    self.provider_metadata,
    response_provider_metadata,
  )
  match json {
    { "message": Object(message), .. } =>
      self.record_json(Json::object(message))
    { "delta": Object(delta), .. } => self.record_json(Json::object(delta))
    _ => ()
  }
}

///|
/// Reset state that Anthropic scopes to one message. Programmatic tool calling
/// can return several message_start/message_stop pairs in one HTTP stream.
fn AnthropicStreamDecoder::begin_message(self : AnthropicStreamDecoder) -> Unit {
  self.block_kinds.clear()
  self.block_ids.clear()
  self.block_names.clear()
  self.block_signatures.clear()
  self.block_redacted_data.clear()
  self.block_citations.clear()
  self.block_data.clear()
  self.block_started.clear()
  self.block_stopped.clear()
  self.block_ready.clear()
  self.block_tool_calls.clear()
  self.block_tool_results.clear()
  self.block_custom.clear()
  self.block_provider_executed.clear()
  self.block_dynamic.clear()
  self.block_tool_metadata.clear()
  self.block_json_response_tools.clear()
  self.source_block_indices.clear()
  self.input_tokens = 0
  self.output_tokens = 0
  self.cache_creation_input_tokens = 0
  self.cache_read_input_tokens = 0
  self.reasoning_tokens = 0
  self.finish_reason = @provider.Unknown("")
  self.finish_reason_raw = None
  self.raw_usage = None
  self.provider_metadata = Map([])
  self.is_json_response_from_tool = false
  self.message_finalized = false
  self.saw_message_stop = false
  self.message_had_tool_call = false
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
    self.block_citations.push([])
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
    self.block_json_response_tools.push(false)
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
    index.to_string()
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
/// Anthropic can place a complete deferred function call directly in
/// message_start.content. AI SDK exposes the same lifecycle as a streamed
/// tool call even though no content block frames follow.
fn AnthropicStreamDecoder::append_message_start_tool_calls(
  self : AnthropicStreamDecoder,
  content : Array[Json],
  events : Array[@provider.StreamEvent],
) -> Unit {
  for part in content {
    match part {
      { "type": "tool_use", "id": String(id), "name": String(wire_name), .. } => {
        let name = self.tool_name_mapping.to_custom_tool_name(wire_name)
        let input = match part {
          { "input": value, .. } => value
          _ => Json::empty_object()
        }
        let arguments = input.stringify()
        let provider_metadata = anthropic_tool_caller_metadata(
          part,
          self.provider_name,
          canonical_metadata=self.canonical_metadata,
          include_custom_provider_metadata=self.include_custom_provider_metadata,
        )
        let call = @provider.ToolCall::new(
          id~,
          name~,
          arguments~,
          provider_metadata~,
        )
        events.push(@provider.ToolInputStart(id~, tool_name=name))
        events.push(@provider.ToolInputDelta(id~, delta=arguments))
        events.push(@provider.ToolInputEnd(id))
        events.push(@provider.ToolCallReady(call))
        self.tool_calls.push(call)
        self.message_had_tool_call = true
      }
      _ => ()
    }
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
        let result : Map[String, Json] = Map([("type", Json::string(name))])
        for entry in fields.iter2() {
          result[entry.0] = entry.1
        }
        Json::object(result)
      }
      _ => input
    }
  } else if name == "code_execution" {
    match input {
      Object(fields) if fields.get("code") is Some(_) &&
        fields.get("type") is None => {
        let result : Map[String, Json] = Map([
          ("type", Json::string("programmatic-tool-call")),
        ])
        for entry in fields.iter2() {
          result[entry.0] = entry.1
        }
        Json::object(result)
      }
      _ => input
    }
  } else {
    input
  }
}

///|
fn anthropic_server_tool_input_type(name : String) -> String? {
  match name {
    "text_editor_code_execution" | "bash_code_execution" => Some(name)
    "code_execution" => Some("programmatic-tool-call")
    _ => None
  }
}

///|
fn anthropic_server_tool_input_delta(
  name : String,
  delta : String,
  first_delta : Bool,
) -> String {
  guard first_delta else { return delta }
  guard anthropic_server_tool_input_type(name) is Some(input_type) else {
    return delta
  }
  match delta.strip_prefix("{") {
    Some(rest) => "{\"type\": \"" + input_type + "\"," + rest.to_owned()
    None => delta
  }
}

///|
/// Normalize Anthropic's wire-format caller into AI SDK provider metadata.
fn anthropic_tool_caller_metadata(
  block : Json,
  provider_name : String,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
) -> Map[String, Json] {
  match block {
    { "caller": Object(caller), .. } =>
      match caller.get("type") {
        Some(String(kind)) => {
          let normalized : Map[String, Json] = Map([
            ("type", Json::string(kind)),
          ])
          match caller.get("tool_id") {
            Some(String(tool_id)) =>
              normalized["toolId"] = Json::string(tool_id)
            _ =>
              match caller.get("toolId") {
                Some(String(tool_id)) =>
                  normalized["toolId"] = Json::string(tool_id)
                _ => ()
              }
          }
          anthropic_resolved_metadata_map(
            provider_name,
            { "caller": Json::object(normalized) },
            canonical_metadata,
            include_custom_provider_metadata,
          )
        }
        _ => Map([])
      }
    _ => Map([])
  }
}

///|
fn anthropic_tool_provider_metadata(
  provider_name : String,
  kind : String,
  server_name : String?,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([("type", Json::string(kind))])
  match server_name {
    Some(value) => fields["serverName"] = Json::string(value)
    None => ()
  }
  anthropic_resolved_metadata_map(
    provider_name,
    Json::object(fields),
    canonical_metadata,
    include_custom_provider_metadata,
  )
}

///|
fn anthropic_snake_to_camel(value : String) -> String {
  let result = StringBuilder::new(size_hint=value.length())
  let mut capitalize = false
  for character in value {
    if character == '_' {
      capitalize = true
    } else if capitalize {
      result.write_char(character.to_ascii_uppercase())
      capitalize = false
    } else {
      result.write_char(character)
    }
  }
  result.to_string()
}

///|
fn anthropic_snake_to_camel_json(value : Json) -> Json {
  match value {
    Object(fields) => {
      let mapped : Map[String, Json] = Map([])
      for entry in fields.iter2() {
        mapped[anthropic_snake_to_camel(entry.0)] = anthropic_snake_to_camel_json(
          entry.1,
        )
      }
      Json::object(mapped)
    }
    Array(values) =>
      Json::array([ for item in values => anthropic_snake_to_camel_json(item) ])
    other => other
  }
}

///|
fn anthropic_object_field(value : Json, name : String, fallback : Json) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(fallback)
    _ => fallback
  }
}

///|
fn anthropic_code_execution_result(content : Json) -> Json {
  let kind = @provider_utils.json_string_field(content, "type").unwrap_or("")
  if kind == "code_execution_result" {
    {
      "type": kind,
      "stdout": anthropic_object_field(content, "stdout", Json::null()),
      "stderr": anthropic_object_field(content, "stderr", Json::null()),
      "return_code": anthropic_object_field(
        content,
        "return_code",
        Json::null(),
      ),
      "content": anthropic_object_field(content, "content", Json::array([])),
    }
  } else if kind == "encrypted_code_execution_result" {
    {
      "type": kind,
      "encrypted_stdout": anthropic_object_field(
        content,
        "encrypted_stdout",
        Json::null(),
      ),
      "stderr": anthropic_object_field(content, "stderr", Json::null()),
      "return_code": anthropic_object_field(
        content,
        "return_code",
        Json::null(),
      ),
      "content": anthropic_object_field(content, "content", Json::array([])),
    }
  } else if kind == "code_execution_tool_result_error" {
    {
      "type": kind,
      "errorCode": anthropic_object_field(content, "error_code", Json::null()),
    }
  } else {
    content
  }
}

///|
fn anthropic_tool_search_result(content : Json) -> Json {
  match content {
    {
      "type": "tool_search_tool_search_result",
      "tool_references": Array(references),
      ..
    } =>
      Json::array(
        [
          for reference in references => {
            match reference {
              { "type": String(kind), "tool_name": String(name), .. } =>
                { "type": kind, "toolName": name }
              other => anthropic_snake_to_camel_json(other)
            }
          }
        ],
      )
    {
      "type": "tool_search_tool_result_error",
      "error_code": String(error_code),
      ..
    } => { "type": "tool_search_tool_result_error", "errorCode": error_code }
    _ => anthropic_snake_to_camel_json(content)
  }
}

///|
fn anthropic_advisor_result(content : Json) -> Json {
  match content {
    { "type": "advisor_result", "text": text, .. } =>
      { "type": "advisor_result", "text": text }
    {
      "type": "advisor_redacted_result",
      "encrypted_content": encrypted_content,
      ..
    } =>
      {
        "type": "advisor_redacted_result",
        "encryptedContent": encrypted_content,
      }
    { "type": "advisor_tool_result_error", "error_code": error_code, .. } =>
      { "type": "advisor_tool_result_error", "errorCode": error_code }
    _ => anthropic_snake_to_camel_json(content)
  }
}

///|
fn anthropic_tool_result_content(kind : String, content : Json) -> Json {
  match kind {
    "web_fetch_tool_result" | "web_search_tool_result" =>
      anthropic_snake_to_camel_json(content)
    "code_execution_tool_result" => anthropic_code_execution_result(content)
    "tool_search_tool_result" => anthropic_tool_search_result(content)
    "advisor_tool_result" => anthropic_advisor_result(content)
    _ => content
  }
}

///|
fn anthropic_tool_search_result_name(
  tool_use_id : String,
  server_tool_names : Map[String, String],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> String {
  match server_tool_names.get(tool_use_id) {
    Some(value) => value
    None => {
      let bm25 = tool_name_mapping.to_custom_tool_name("tool_search_tool_bm25")
      let regex = tool_name_mapping.to_custom_tool_name(
        "tool_search_tool_regex",
      )
      if bm25 != "tool_search_tool_bm25" {
        "tool_search_tool_bm25"
      } else if regex != "tool_search_tool_regex" {
        "tool_search_tool_regex"
      } else {
        "tool_search_tool_regex"
      }
    }
  }
}

///|
fn anthropic_tool_result_name(
  kind : String,
  tool_use_id : String,
  server_tool_names : Map[String, String],
  mcp_tool_names : Map[String, String],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> String {
  match kind {
    "mcp_tool_result" => mcp_tool_names.get(tool_use_id).unwrap_or("mcp_tool")
    "web_fetch_tool_result" => "web_fetch"
    "web_search_tool_result" => "web_search"
    "code_execution_tool_result"
    | "bash_code_execution_tool_result"
    | "text_editor_code_execution_tool_result" => "code_execution"
    "tool_search_tool_result" =>
      anthropic_tool_search_result_name(
        tool_use_id, server_tool_names, tool_name_mapping,
      )
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
  server_tool_names : Map[String, String],
  mcp_tool_names : Map[String, String],
  mcp_tool_metadata : Map[String, Map[String, Json]],
  tool_name_mapping : @provider_utils.ToolNameMapping,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
) -> @provider.ToolResult? {
  let kind = @provider_utils.json_string_field(block, "type").unwrap_or("")
  let tool_use_id = @provider_utils.json_string_field(block, "tool_use_id").unwrap_or(
    @provider_utils.json_string_field(block, "toolUseId").unwrap_or(""),
  )
  guard tool_use_id != "" else { return None }
  let raw_result = anthropic_response_field(block, ["content", "result"]).unwrap_or(
    Json::empty_object(),
  )
  let result = anthropic_tool_result_content(kind, raw_result)
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
        anthropic_tool_provider_metadata(
          provider_name,
          "mcp-tool-use",
          None,
          canonical_metadata~,
          include_custom_provider_metadata~,
        ),
      )
    _ => Map([])
  }
  Some(
    @provider.ToolResult::new(
      tool_call_id=tool_use_id,
      tool_name=tool_name_mapping.to_custom_tool_name(
        anthropic_tool_result_name(
          kind, tool_use_id, server_tool_names, mcp_tool_names, tool_name_mapping,
        ),
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
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
) -> @provider.GeneratedCustomContent {
  @provider.GeneratedCustomContent::new(
    kind~,
    provider_metadata=anthropic_resolved_metadata_map(
      provider_name,
      { "type": kind, "raw": block },
      canonical_metadata,
      include_custom_provider_metadata,
    ),
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
  self.message_had_tool_call = true
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
    if !self.uses_json_response_tool && self.block_started[index] {
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
    if self.block_json_response_tools[index] {
      if !self.block_started[index] {
        self.start_text_block(index, events)
      }
      events.push(@provider.TextEnd(self.block_id(index, "text")))
      self.block_ready[index] = true
    } else if kind == "mcp_tool_use" && self.block_ready[index] {
      ()
    } else {
      if !self.block_started[index] {
        self.start_tool_block(index, events)
      }
      events.push(@provider.ToolInputEnd(self.block_id(index, "tool")))
      self.finish_tool_block(index, events)
    }
  } else if anthropic_is_tool_result_kind(kind) {
    match (self.block_ready[index], self.block_tool_results[index]) {
      (false, Some(result)) => {
        events.push(@provider.ToolResultReady(result))
        self.block_ready[index] = true
      }
      _ => ()
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
        self.metadata_map({ "usage": raw }),
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
  if self.message_finalized || self.finalized {
    return []
  }
  self.message_finalized = true
  let events : Array[@provider.StreamEvent] = []
  for index, kind in self.block_kinds {
    if anthropic_is_tool_call_kind(kind) &&
      !self.block_json_response_tools[index] &&
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
  let reason = if self.finish_reason_raw == Some("tool_use") &&
    self.is_json_response_from_tool {
    @provider.Stop
  } else {
    match self.finish_reason {
      @provider.Unknown("") =>
        if self.message_had_tool_call {
          @provider.ToolCalls
        } else {
          @provider.Stop
        }
      other => other
    }
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
  if event_type != "" && event_type != "error" && event_type != "ping" {
    self.received_data_event = true
  }
  match event_type {
    "message_start" => {
      let metadata = match json {
        { "message": message, .. } =>
          @provider_utils.create_language_model_response_metadata(
            id?=@provider_utils.json_string_field(message, "id"),
            model?=@provider_utils.json_string_field(message, "model"),
            created?=@provider_utils.json_int_field_opt(message, "created_at"),
          )
        _ => @provider.ResponseMetadata::empty()
      }
      if !metadata.is_empty() {
        self.response_metadata = Some(
          @provider.merge_response_metadata(self.response_metadata, metadata),
        )
      }
      events.push(@provider.ResponseMetadataReady(metadata))
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
      match json {
        { "message": { "content": Array(content), .. }, .. } =>
          self.append_message_start_tool_calls(content, events)
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
          if kind == "tool_use" &&
            self.uses_json_response_tool &&
            self.block_names[i] == "json" {
            self.block_json_response_tools[i] = true
            self.is_json_response_from_tool = true
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
          if kind == "tool_use" {
            self.block_tool_metadata[i] = anthropic_tool_caller_metadata(
              Json::object(block),
              self.provider_name,
              canonical_metadata=self.canonical_metadata,
              include_custom_provider_metadata=self.include_custom_provider_metadata,
            )
          }
          if kind == "server_tool_use" {
            let original_name = self.block_names[i]
            let id = self.block_ids[i]
            if id != "" {
              self.server_tool_names[id] = original_name
            }
            self.block_names[i] = self.tool_name_mapping.to_custom_tool_name(
              anthropic_server_tool_name(original_name),
            )
            self.block_provider_executed[i] = true
            if self.mark_code_execution_dynamic &&
              anthropic_server_tool_name(original_name) == "code_execution" {
              self.block_dynamic[i] = true
            }
            self.block_tool_metadata[i] = anthropic_tool_provider_metadata(
              self.provider_name,
              "server-tool-use",
              None,
              canonical_metadata=self.canonical_metadata,
              include_custom_provider_metadata=self.include_custom_provider_metadata,
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
              canonical_metadata=self.canonical_metadata,
              include_custom_provider_metadata=self.include_custom_provider_metadata,
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
            if !self.uses_json_response_tool {
              self.start_text_block(i, events)
            }
          } else if kind == "thinking" || kind == "redacted_thinking" {
            self.start_reasoning_block(i, events)
          } else if kind == "compaction" {
            self.start_text_block(i, events)
          } else if anthropic_is_tool_call_kind(kind) {
            if self.block_json_response_tools[i] {
              self.start_text_block(i, events)
            } else if kind == "mcp_tool_use" {
              self.finish_tool_block(i, events)
            } else {
              self.start_tool_block(i, events)
            }
          } else if anthropic_is_tool_result_kind(kind) {
            if kind == "web_fetch_tool_result" {
              match anthropic_web_fetch_citation_document(Json::object(block)) {
                Some(document) => self.citation_documents.push(document)
                None => ()
              }
            }
            match
              anthropic_tool_result_from_block(
                Json::object(block),
                self.provider_name,
                self.server_tool_names,
                self.mcp_tool_names,
                self.mcp_tool_metadata,
                self.tool_name_mapping,
                canonical_metadata=self.canonical_metadata,
                include_custom_provider_metadata=self.include_custom_provider_metadata,
              ) {
              Some(result) => {
                self.block_tool_results[i] = Some(result)
                self.tool_results.push(result)
                events.push(@provider.ToolResultReady(result))
                self.block_ready[i] = true
                if kind == "web_search_tool_result" {
                  match block.get("content") {
                    Some(content) =>
                      self.append_anthropic_web_search_sources(
                        i, content, events,
                      )
                    None => ()
                  }
                }
              }
              None => ()
            }
          } else if kind != "" && kind != "fallback" {
            let custom = anthropic_custom_block(
              kind,
              Json::object(block),
              self.provider_name,
              canonical_metadata=self.canonical_metadata,
              include_custom_provider_metadata=self.include_custom_provider_metadata,
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
            if !self.uses_json_response_tool {
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
          } else if delta_type == "input_json_delta" {
            let value = match delta.get("partial_json") {
              Some(String(value)) => value
              _ => ""
            }
            if value != "" {
              if self.block_kinds[i] == "" {
                self.block_kinds[i] = "tool_use"
              }
              if self.block_json_response_tools[i] {
                self.start_text_block(i, events)
                self.text.write_string(value)
                self.block_data[i].write_string(value)
                events.push(
                  @provider.TextDelta(id=self.block_id(i, "text"), delta=value),
                )
              } else {
                self.start_tool_block(i, events)
                let emitted_delta = if self.block_kinds[i] == "server_tool_use" {
                  let original_name = self.server_tool_names
                    .get(self.block_ids[i])
                    .unwrap_or("")
                  anthropic_server_tool_input_delta(
                    original_name,
                    value,
                    self.block_data[i].to_string().is_empty(),
                  )
                } else {
                  value
                }
                self.block_data[i].write_string(emitted_delta)
                events.push(
                  @provider.ToolInputDelta(
                    id=self.block_id(i, "tool"),
                    delta=emitted_delta,
                  ),
                )
              }
            }
          } else if delta_type == "compaction_delta" {
            match delta.get("content") {
              Some(String(value)) => {
                self.block_kinds[i] = "compaction"
                self.start_text_block(i, events)
                self.block_data[i].write_string(value)
                events.push(
                  @provider.TextDelta(id=self.block_id(i, "text"), delta=value),
                )
              }
              _ => ()
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
                if !(self.uses_json_response_tool &&
                  self.block_kinds[i] == "text") {
                  self.append_anthropic_citations(i, [citation], events)
                }
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
    "message_stop" => {
      let events = self.final_events()
      self.saw_message_stop = true
      (events, false)
    }
    "error" => {
      let (message, error_type, response_body) = match json {
        { "error": Object(error), .. } => {
          let message = match error.get("message") {
            Some(String(value)) => value
            _ => json.stringify()
          }
          let error_type = match error.get("type") {
            Some(String(value)) => value
            _ => ""
          }
          (message, error_type, Json::object(error).stringify())
        }
        _ => (json.stringify(), "", json.stringify())
      }
      if !self.received_data_event {
        let overloaded = error_type == "overloaded_error"
        raise @provider_utils.SseProviderError(
          message~,
          status_code=if overloaded { 529 } else { 500 },
          response_body~,
          is_retryable=overloaded,
        )
      }
      self.finish_reason_raw = Some("error")
      self.finish_reason = @provider.Error
      let error_data = match json {
        { "error": value, .. } => value
        _ => json
      }
      events.push(
        @provider.StreamError(
          @provider.StreamErrorInfo::new(message, data=error_data),
        ),
      )
      // AI SDK forwards an in-stream Anthropic error as the terminal stream
      // part. There is no synthetic content end or finish part afterwards.
      self.finalized = true
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
fn anthropic_stream_chunk_validation_error(json : Json) -> String? {
  let event_type = match json {
    { "type": String(value), .. } => value
    Object(_) =>
      return Some(
        "Anthropic stream chunk must contain a string type discriminator",
      )
    _ => return Some("Anthropic stream chunk must be a JSON object")
  }
  match event_type {
    "message_start" =>
      match json {
        { "message": { "usage": { "input_tokens": Number(_), .. }, .. }, .. } =>
          None
        _ =>
          Some(
            "Anthropic message_start chunk must contain message.usage.input_tokens",
          )
      }
    "content_block_start" =>
      match json {
        { "index": Number(_), "content_block": { "type": String(_), .. }, .. } =>
          None
        _ =>
          Some(
            "Anthropic content_block_start chunk must contain a numeric index and typed content_block",
          )
      }
    "content_block_delta" =>
      match json {
        { "index": Number(_), "delta": { "type": String(_), .. }, .. } => None
        _ =>
          Some(
            "Anthropic content_block_delta chunk must contain a numeric index and typed delta",
          )
      }
    "content_block_stop" =>
      match json {
        { "index": Number(_), .. } => None
        _ =>
          Some(
            "Anthropic content_block_stop chunk must contain a numeric index",
          )
      }
    "message_delta" =>
      match json {
        { "delta": Object(_), "usage": { "output_tokens": Number(_), .. }, .. } =>
          None
        _ =>
          Some(
            "Anthropic message_delta chunk must contain delta and usage.output_tokens",
          )
      }
    "error" =>
      match json {
        { "error": { "type": String(_), "message": String(_), .. }, .. } => None
        _ =>
          Some(
            "Anthropic error chunk must contain error.type and error.message",
          )
      }
    "message_stop" | "ping" => None
    _ => Some("Unsupported Anthropic stream chunk type: \{event_type}")
  }
}

///|
fn AnthropicStreamDecoder::invalid_stream_chunk(
  self : AnthropicStreamDecoder,
  message : String,
  data : Json,
) -> @provider_utils.SseDecodeBatch[@provider.StreamEvent] {
  let events : Array[@provider.StreamEvent] = []
  if self.include_raw_chunks {
    events.push(@provider.Raw(data))
  }
  events.push(
    @provider.StreamError(@provider.StreamErrorInfo::new(message, data~)),
  )
  { events, consumed_event: true, done: false }
}

///|
fn AnthropicStreamDecoder::decode_data(
  self : AnthropicStreamDecoder,
  data : String,
) -> @provider_utils.SseDecodeBatch[@provider.StreamEvent] raise {
  if data.trim() == "[DONE]" {
    let events = self.final_events()
    self.finalized = true
    return { events, consumed_event: true, done: true }
  }
  let json = @json.parse(data) catch {
    error =>
      return self.invalid_stream_chunk(
        "Anthropic stream decode error: \{error}; data: \{data}",
        Json::string(data),
      )
  }
  if anthropic_stream_chunk_validation_error(json) is Some(message) {
    return self.invalid_stream_chunk(message, json)
  }
  if @provider_utils.json_string_field(json, "type") == Some("message_start") {
    self.begin_message()
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
fn AnthropicStreamDecoder::feed_line(
  self : AnthropicStreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.StreamEvent] raise {
  match self.sse.feed_line(raw) {
    Some(data) => self.decode_data(data)
    None => @provider_utils.SseDecodeBatch::empty(self.finalized)
  }
}

///|
/// Flush a final unterminated `data:` event before reporting EOF.
fn AnthropicStreamDecoder::flush_buffered(
  self : AnthropicStreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.StreamEvent] raise {
  match self.sse.flush() {
    Some(data) => {
      let batch = self.decode_data(data)
      if !batch.done && self.saw_message_stop {
        self.finalized = true
        { ..batch, done: true }
      } else {
        batch
      }
    }
    None => {
      if !self.finalized && self.saw_message_stop {
        self.finalized = true
      }
      @provider_utils.SseDecodeBatch::empty(self.finalized)
    }
  }
}

///|
/// Return lossless V4 usage accumulated from message_start/message_delta.
fn AnthropicStreamDecoder::v4_usage(
  self : AnthropicStreamDecoder,
) -> @provider.LanguageModelV4Usage {
  anthropic_v4_usage_from_raw(self.raw_usage)
}

///|
/// Return the normalized and provider-native Anthropic stop reason.
fn AnthropicStreamDecoder::v4_finish_reason(
  self : AnthropicStreamDecoder,
) -> @provider.LanguageModelV4FinishReason {
  anthropic_v4_finish_reason_from_raw(
    self.finish_reason_raw,
    self.is_json_response_from_tool,
  )
}

///|
/// Snapshot provider metadata without exposing the decoder's mutable map.
fn AnthropicStreamDecoder::provider_metadata_snapshot(
  self : AnthropicStreamDecoder,
) -> Map[String, Json] {
  anthropic_complete_provider_metadata(
    @provider.copy_provider_metadata(self.provider_metadata),
    self.provider_name,
    self.canonical_metadata,
    self.include_custom_provider_metadata,
  )
}

///|
/// Return response identity accumulated from Anthropic stream frames.
fn AnthropicStreamDecoder::response_metadata_snapshot(
  self : AnthropicStreamDecoder,
) -> @provider.ResponseMetadata? {
  self.response_metadata
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
    _ => @provider_utils.create_null_language_model_usage()
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
fn anthropic_v4_finish_reason_from_raw(
  raw : String?,
  is_json_response_from_tool : Bool,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("pause_turn") | Some("end_turn") | Some("stop_sequence") =>
      @provider.V4FinishStop
    Some("refusal") => @provider.V4FinishContentFilter
    Some("tool_use") =>
      if is_json_response_from_tool {
        @provider.V4FinishStop
      } else {
        @provider.V4FinishToolCalls
      }
    Some("max_tokens") | Some("model_context_window_exceeded") =>
      @provider.V4FinishLength
    _ => @provider.V4FinishOther
  }
  { unified, raw }
}

///|
priv struct AnthropicDecodedResponse {
  content : Array[@provider.LanguageModelV4Content]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  provider_metadata : Map[String, Json]
  response : @provider.ResponseMetadata?
}

///|
/// Decode one non-streaming Anthropic response with an explicit metadata
/// policy used by the high-level language model.
fn decode_messages_response_with_metadata(
  json : Json,
  provider_name~ : String,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
  mark_code_execution_dynamic~ : Bool,
  uses_json_response_tool~ : Bool,
  tool_name_mapping~ : @provider_utils.ToolNameMapping,
  id_generator~ : @provider_utils.IdGenerator,
  citation_documents~ : Array[AnthropicCitationDocument],
) -> AnthropicDecodedResponse raise {
  if anthropic_response_error(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="Anthropic request failed: \{message}",
      data=json,
    )
  }
  let content : Array[@provider.LanguageModelV4Content] = []
  let generate_id = id_generator
  let mut is_json_response_from_tool = false
  let server_tool_names : Map[String, String] = Map([])
  let mcp_tool_names : Map[String, String] = Map([])
  let mcp_tool_metadata : Map[String, Map[String, Json]] = Map([])
  let resolved_citation_documents = citation_documents.copy()
  let resolved_tool_name_mapping = tool_name_mapping
  match json {
    { "content": Array(blocks), .. } =>
      for index, block in blocks {
        match block {
          {
            "type": "text",
            "text": String(value),
            "citations": Array(citations),
            ..
          } =>
            if !uses_json_response_tool {
              let web_search_citations : Array[Json] = []
              for citation in citations {
                if @provider_utils.json_string_field(citation, "type")
                  is Some("web_search_result_location") {
                  web_search_citations.push(citation)
                }
              }
              content.push(
                @provider.LanguageModelV4Content::text(
                  value,
                  provider_metadata=if web_search_citations.length() == 0 {
                    Map([])
                  } else {
                    anthropic_resolved_metadata_map(
                      provider_name,
                      { "citations": Json::array(web_search_citations) },
                      canonical_metadata,
                      include_custom_provider_metadata,
                    )
                  },
                ),
              )
              for citation_index, citation in citations {
                match
                  anthropic_citation_source(
                    citation,
                    resolved_citation_documents,
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
                    canonical_metadata~,
                    include_custom_provider_metadata~,
                  ) {
                  Some(source) =>
                    content.push(
                      @provider.V4SourceOutput(
                        @provider.LanguageModelV4Source::from_generated_source(
                          source,
                        ),
                      ),
                    )
                  None => ()
                }
              }
            }
          { "type": "text", "text": String(value), .. } =>
            if !uses_json_response_tool {
              content.push(@provider.LanguageModelV4Content::text(value))
            }
          {
            "type": "thinking",
            "thinking": String(value),
            "signature": String(signature),
            ..
          } => {
            let metadata : Map[String, Json] = anthropic_resolved_metadata_map(
              provider_name,
              { "signature": signature },
              canonical_metadata,
              include_custom_provider_metadata,
            )
            content.push(
              @provider.LanguageModelV4Content::reasoning(
                value,
                provider_metadata=metadata,
              ),
            )
          }
          { "type": "thinking", "thinking": String(value), .. } =>
            content.push(@provider.LanguageModelV4Content::reasoning(value))
          { "type": "redacted_thinking", "data": String(data), .. } =>
            content.push(
              @provider.LanguageModelV4Content::reasoning(
                "",
                provider_metadata=anthropic_resolved_metadata_map(
                  provider_name,
                  { "redactedData": data },
                  canonical_metadata,
                  include_custom_provider_metadata,
                ),
              ),
            )
          { "type": "compaction", "content": String(value), .. } =>
            content.push(
              @provider.LanguageModelV4Content::text(
                value,
                provider_metadata=anthropic_resolved_metadata_map(
                  provider_name,
                  { "type": "compaction" },
                  canonical_metadata,
                  include_custom_provider_metadata,
                ),
              ),
            )
          {
            "type": "tool_use",
            "id": String(id),
            "name": String(name),
            "input": input,
            ..
          } =>
            if uses_json_response_tool && name == "json" {
              is_json_response_from_tool = true
              content.push(
                @provider.LanguageModelV4Content::text(input.stringify()),
              )
            } else {
              content.push(
                @provider.LanguageModelV4Content::tool_call({
                  tool_call_id: id,
                  tool_name: resolved_tool_name_mapping.to_custom_tool_name(
                    name,
                  ),
                  input: input.stringify(),
                  provider_executed: false,
                  dynamic: false,
                  provider_metadata: anthropic_tool_caller_metadata(
                    block,
                    provider_name,
                    canonical_metadata~,
                    include_custom_provider_metadata~,
                  ),
                }),
              )
            }
          { "type": "tool_use", "name": String(name), "input": input, .. } =>
            if uses_json_response_tool && name == "json" {
              is_json_response_from_tool = true
              content.push(
                @provider.LanguageModelV4Content::text(input.stringify()),
              )
            } else {
              content.push(
                @provider.LanguageModelV4Content::tool_call({
                  tool_call_id: generate_id(),
                  tool_name: resolved_tool_name_mapping.to_custom_tool_name(
                    name,
                  ),
                  input: input.stringify(),
                  provider_executed: false,
                  dynamic: false,
                  provider_metadata: anthropic_tool_caller_metadata(
                    block,
                    provider_name,
                    canonical_metadata~,
                    include_custom_provider_metadata~,
                  ),
                }),
              )
            }
          {
            "type": "server_tool_use",
            "id": String(id),
            "name": String(name),
            "input": input,
            ..
          } => {
            if id != "" {
              server_tool_names[id] = name
            }
            let normalized_name = anthropic_server_tool_name(name)
            let normalized_input = anthropic_server_tool_input(name, input)
            content.push(
              @provider.LanguageModelV4Content::tool_call({
                tool_call_id: id,
                tool_name: resolved_tool_name_mapping.to_custom_tool_name(
                  normalized_name,
                ),
                input: normalized_input.stringify(),
                provider_executed: true,
                dynamic: mark_code_execution_dynamic &&
                normalized_name == "code_execution",
                provider_metadata: anthropic_tool_provider_metadata(
                  provider_name,
                  "server-tool-use",
                  None,
                  canonical_metadata~,
                  include_custom_provider_metadata~,
                ),
              }),
            )
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
              canonical_metadata~,
              include_custom_provider_metadata~,
            )
            let custom_name = resolved_tool_name_mapping.to_custom_tool_name(
              name,
            )
            mcp_tool_names[id] = custom_name
            mcp_tool_metadata[id] = metadata
            content.push(
              @provider.LanguageModelV4Content::tool_call({
                tool_call_id: id,
                tool_name: custom_name,
                input: input.stringify(),
                provider_executed: true,
                dynamic: true,
                provider_metadata: metadata,
              }),
            )
          }
          { "type": String(kind), .. } if anthropic_is_tool_result_kind(kind) => {
            if kind == "web_fetch_tool_result" {
              match anthropic_web_fetch_citation_document(block) {
                Some(document) => resolved_citation_documents.push(document)
                None => ()
              }
            }
            match
              anthropic_tool_result_from_block(
                block,
                provider_name,
                server_tool_names,
                mcp_tool_names,
                mcp_tool_metadata,
                resolved_tool_name_mapping,
                canonical_metadata~,
                include_custom_provider_metadata~,
              ) {
              Some(result) => {
                content.push(
                  @provider.LanguageModelV4Content::tool_result(
                    @provider.LanguageModelV4ToolResult::from_tool_result(
                      result,
                    ),
                  ),
                )
                if kind == "web_search_tool_result" {
                  let raw_result = anthropic_response_field(block, [
                    "content", "result",
                  ]).unwrap_or(Json::empty_object())
                  for
                    source in anthropic_web_search_sources(
                      raw_result,
                      provider_name,
                      generate_id,
                      canonical_metadata~,
                      include_custom_provider_metadata~,
                    ) {
                    content.push(
                      @provider.V4SourceOutput(
                        @provider.LanguageModelV4Source::from_generated_source(
                          source,
                        ),
                      ),
                    )
                  }
                }
              }
              None => ()
            }
          }
          { "type": "fallback", .. } => ()
          { "type": String(kind), .. } if kind != "" => {
            let custom = anthropic_custom_block(
              kind,
              block,
              provider_name,
              canonical_metadata~,
              include_custom_provider_metadata~,
            )
            content.push(
              @provider.LanguageModelV4Content::custom(
                kind=custom.kind,
                provider_metadata=custom.provider_metadata,
              ),
            )
          }
          _ => ()
        }
      }
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Anthropic response has no content array",
        data=json,
      )
  }
  let response_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created_at"),
  )
  let raw_provider_metadata = @provider_utils.provider_metadata_from_json(
    json, provider_name,
  )
  let response_provider_metadata = anthropic_response_provider_metadata(
    json,
    provider_name,
    canonical_metadata~,
    include_custom_provider=include_custom_provider_metadata,
  )
  if canonical_metadata && raw_provider_metadata.get(provider_name) is Some(_) {
    match response_provider_metadata.get("anthropic") {
      Some(value) => response_provider_metadata[provider_name] = value
      None => ()
    }
  }
  let provider_metadata = anthropic_complete_provider_metadata(
    @provider.merge_provider_metadata(
      raw_provider_metadata, response_provider_metadata,
    ),
    provider_name,
    canonical_metadata,
    include_custom_provider_metadata,
  )
  {
    content,
    finish_reason: anthropic_v4_finish_reason_from_raw(
      anthropic_response_stop_reason(json),
      is_json_response_from_tool,
    ),
    usage: anthropic_v4_usage_from_raw(anthropic_response_usage_json(json)),
    provider_metadata,
    response: if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
  }
}

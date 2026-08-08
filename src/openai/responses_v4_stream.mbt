///|
priv struct OpenAIResponsesV4StreamMetadata {
  provider_name : String
  store : Bool
  shell_provider_executed : Bool
  message_ids : Array[String]
  message_phases : Array[String]
  message_annotations : Array[Array[Json]]
  reasoning_ids : Array[String]
  reasoning_encrypted_content : Array[Json]
  summary_ids : Array[String]
  summary_item_ids : Array[String]
  summary_status : Array[String]
}

///|
fn OpenAIResponsesV4StreamMetadata::new(
  provider_name : String,
  store~ : Bool,
  shell_provider_executed~ : Bool,
) -> OpenAIResponsesV4StreamMetadata {
  {
    provider_name,
    store,
    shell_provider_executed,
    message_ids: [],
    message_phases: [],
    message_annotations: [],
    reasoning_ids: [],
    reasoning_encrypted_content: [],
    summary_ids: [],
    summary_item_ids: [],
    summary_status: [],
  }
}

///|
fn openai_v4_stream_find_id(values : Array[String], id : String) -> Int? {
  for index, value in values {
    if value == id {
      return Some(index)
    }
  }
  None
}

///|
fn OpenAIResponsesV4StreamMetadata::ensure_message(
  self : OpenAIResponsesV4StreamMetadata,
  id : String,
) -> Int {
  match openai_v4_stream_find_id(self.message_ids, id) {
    Some(index) => index
    None => {
      self.message_ids.push(id)
      self.message_phases.push("")
      self.message_annotations.push([])
      self.message_ids.length() - 1
    }
  }
}

///|
fn OpenAIResponsesV4StreamMetadata::ensure_reasoning(
  self : OpenAIResponsesV4StreamMetadata,
  id : String,
) -> Int {
  match openai_v4_stream_find_id(self.reasoning_ids, id) {
    Some(index) => index
    None => {
      self.reasoning_ids.push(id)
      self.reasoning_encrypted_content.push(Json::null())
      self.reasoning_ids.length() - 1
    }
  }
}

///|
fn OpenAIResponsesV4StreamMetadata::ensure_summary(
  self : OpenAIResponsesV4StreamMetadata,
  summary_id : String,
  item_id : String,
) -> Int {
  match openai_v4_stream_find_id(self.summary_ids, summary_id) {
    Some(index) => index
    None => {
      self.summary_ids.push(summary_id)
      self.summary_item_ids.push(item_id)
      self.summary_status.push("active")
      self.summary_ids.length() - 1
    }
  }
}

///|
fn openai_v4_stream_item_id(id : String) -> String {
  let parts = [ for part in id.split(":") => part ]
  if parts.length() > 0 {
    parts[0].to_owned()
  } else {
    id
  }
}

///|
fn openai_v4_stream_raw_type(raw : Json?) -> String {
  match raw {
    Some(value) =>
      @provider_utils.json_string_field(value, "type").unwrap_or("")
    None => ""
  }
}

///|
fn openai_v4_stream_item(raw : Json) -> Json? {
  match raw {
    { "item": item, .. } => Some(item)
    _ => None
  }
}

///|
fn OpenAIResponsesV4StreamMetadata::reasoning_metadata(
  self : OpenAIResponsesV4StreamMetadata,
  item_id : String,
  include_encrypted_content : Bool,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  if include_encrypted_content {
    let index = self.ensure_reasoning(item_id)
    fields["reasoningEncryptedContent"] = self.reasoning_encrypted_content[index]
  }
  openai_responses_item_metadata(
    self.provider_name,
    item_id,
    extra_fields=fields,
  )
}

///|
fn OpenAIResponsesV4StreamMetadata::text_metadata(
  self : OpenAIResponsesV4StreamMetadata,
  item_id : String,
  include_annotations : Bool,
) -> Map[String, Json] {
  let index = self.ensure_message(item_id)
  let fields : Map[String, Json] = Map([])
  if self.message_phases[index] != "" {
    fields["phase"] = Json::string(self.message_phases[index])
  }
  if include_annotations && self.message_annotations[index].length() > 0 {
    fields["annotations"] = Json::array(
      [
        for annotation in self.message_annotations[index] => annotation
      ],
    )
  }
  openai_responses_item_metadata(
    self.provider_name,
    item_id,
    extra_fields=fields,
  )
}

///|
fn OpenAIResponsesV4StreamMetadata::record_output_item(
  self : OpenAIResponsesV4StreamMetadata,
  item : Json,
) -> Unit {
  let item_id = @provider_utils.json_string_field(item, "id").unwrap_or("")
  let kind = @provider_utils.json_string_field(item, "type").unwrap_or("")
  if item_id == "" {
    return
  }
  if kind == "message" {
    let index = self.ensure_message(item_id)
    if @provider_utils.json_string_field(item, "phase") is Some(phase) {
      self.message_phases[index] = phase
    }
  } else if kind == "reasoning" {
    let index = self.ensure_reasoning(item_id)
    self.reasoning_encrypted_content[index] = match item {
      { "encrypted_content": value, .. } => value
      _ => Json::null()
    }
    let _ = self.ensure_summary("{item_id}:0", item_id)
  }
}

///|
fn OpenAIResponsesV4StreamMetadata::finish_pending_reasoning(
  self : OpenAIResponsesV4StreamMetadata,
  item_id : String,
  include_encrypted_content : Bool,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  for index, summary_item_id in self.summary_item_ids {
    if summary_item_id == item_id &&
      (
        self.summary_status[index] == "active" ||
        self.summary_status[index] == "can-conclude"
      ) {
      self.summary_status[index] = "concluded"
      events.push(
        @provider.V4ReasoningEnd(
          id=self.summary_ids[index],
          provider_metadata=self.reasoning_metadata(
            item_id, include_encrypted_content,
          ),
        ),
      )
    }
  }
  events
}

///|
/// Observe a provider-native frame and emit V4 lifecycle parts that have no
/// faithful legacy `StreamEvent` equivalent.
fn OpenAIResponsesV4StreamMetadata::observe_raw(
  self : OpenAIResponsesV4StreamMetadata,
  raw : Json,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  let event_type = @provider_utils.json_string_field(raw, "type").unwrap_or("")
  if event_type == "response.output_item.added" {
    match openai_v4_stream_item(raw) {
      Some(item) => self.record_output_item(item)
      None => ()
    }
  } else if event_type == "response.output_text.annotation.added" {
    let item_id = @provider_utils.json_string_field(raw, "item_id").unwrap_or(
      "",
    )
    match raw {
      { "annotation": annotation, .. } if item_id != "" => {
        let index = self.ensure_message(item_id)
        self.message_annotations[index].push(annotation)
      }
      _ => ()
    }
  } else if event_type == "response.reasoning_summary_part.added" {
    let item_id = @provider_utils.json_string_field(raw, "item_id").unwrap_or(
      "reasoning-0",
    )
    let summary_index = @provider_utils.json_int_field(raw, "summary_index")
    if summary_index > 0 {
      for index, summary_item_id in self.summary_item_ids {
        if summary_item_id == item_id &&
          self.summary_status[index] == "can-conclude" {
          self.summary_status[index] = "concluded"
          events.push(
            @provider.V4ReasoningEnd(
              id=self.summary_ids[index],
              provider_metadata=self.reasoning_metadata(item_id, false),
            ),
          )
        }
      }
    }
    let summary_id = "{item_id}:{summary_index}"
    let index = self.ensure_summary(summary_id, item_id)
    self.summary_status[index] = "active"
  } else if event_type == "response.reasoning_summary_text.delta" ||
    event_type == "response.reasoning_text.delta" {
    let item_id = @provider_utils.json_string_field(raw, "item_id").unwrap_or(
      "reasoning-0",
    )
    let summary_id = if event_type == "response.reasoning_summary_text.delta" {
      "{item_id}:\{@provider_utils.json_int_field(raw, "summary_index")}"
    } else {
      item_id
    }
    let index = self.ensure_summary(summary_id, item_id)
    self.summary_status[index] = "active"
  } else if event_type == "response.reasoning_summary_part.done" {
    let item_id = @provider_utils.json_string_field(raw, "item_id").unwrap_or(
      "reasoning-0",
    )
    let summary_id = "{item_id}:\{@provider_utils.json_int_field(raw, "summary_index")}"
    let index = self.ensure_summary(summary_id, item_id)
    self.summary_status[index] = if self.store {
      "concluded"
    } else {
      "can-conclude"
    }
  } else if event_type == "response.output_item.done" {
    match openai_v4_stream_item(raw) {
      Some(item) => {
        self.record_output_item(item)
        let kind = @provider_utils.json_string_field(item, "type").unwrap_or("")
        let item_id = @provider_utils.json_string_field(item, "id").unwrap_or(
          "",
        )
        if kind == "message" && item_id != "" {
          events.push(
            @provider.V4TextEnd(
              id=item_id,
              provider_metadata=self.text_metadata(item_id, true),
            ),
          )
        } else if kind == "reasoning" && item_id != "" {
          for event in self.finish_pending_reasoning(item_id, true) {
            events.push(event)
          }
        }
      }
      None => ()
    }
  }
  events
}

///|
fn OpenAIResponsesV4StreamMetadata::tool_start_provider_executed(
  self : OpenAIResponsesV4StreamMetadata,
  raw : Json?,
) -> Bool {
  match raw {
    Some({ "item": item, .. }) => {
      let kind = @provider_utils.json_string_field(item, "type").unwrap_or("")
      kind == "web_search_call" ||
      kind == "code_interpreter_call" ||
      (
        kind == "tool_search_call" &&
        @provider_utils.json_string_field(item, "execution").unwrap_or("server") ==
        "server"
      ) ||
      (kind == "shell_call" && self.shell_provider_executed)
    }
    _ => false
  }
}

///|
fn OpenAIResponsesV4StreamMetadata::tool_input_end_metadata(
  self : OpenAIResponsesV4StreamMetadata,
  raw : Json?,
) -> Map[String, Json] {
  match raw {
    Some(
      {
        "item": {
          "type": "function_call",
          "namespace": String(namespace_value),
          ..
        },
        ..
      }
    ) =>
      Map([
        (
          openai_responses_provider_metadata_key(self.provider_name),
          { "namespace": namespace_value },
        ),
      ])
    _ => Map([])
  }
}

///|
fn OpenAIResponsesV4StreamMetadata::v4_stream_part(
  self : OpenAIResponsesV4StreamMetadata,
  event : @provider.StreamEvent,
  raw : Json?,
) -> @provider.LanguageModelV4StreamPart? {
  let raw_type = openai_v4_stream_raw_type(raw)
  match event {
    @provider.StreamStart => Some(@provider.V4StreamStart(warnings=[]))
    @provider.Warning(_) => None
    @provider.TextStart(id) =>
      Some(
        @provider.V4TextStart(
          id~,
          provider_metadata=self.text_metadata(id, false),
        ),
      )
    @provider.TextDelta(id~, delta~) =>
      Some(@provider.V4TextDelta(id~, delta~, provider_metadata=Map([])))
    @provider.TextEnd(id) =>
      if raw_type == "response.output_text.done" ||
        raw_type == "response.refusal.done" ||
        raw_type == "response.output_item.done" {
        None
      } else {
        Some(
          @provider.V4TextEnd(
            id~,
            provider_metadata=self.text_metadata(id, true),
          ),
        )
      }
    @provider.ReasoningStart(id) => {
      let item_id = openai_v4_stream_item_id(id)
      Some(
        @provider.V4ReasoningStart(
          id~,
          provider_metadata=self.reasoning_metadata(item_id, true),
        ),
      )
    }
    @provider.ReasoningDelta(id~, delta~) =>
      Some(
        @provider.V4ReasoningDelta(
          id~,
          delta~,
          provider_metadata=self.reasoning_metadata(
            openai_v4_stream_item_id(id),
            false,
          ),
        ),
      )
    @provider.ReasoningEnd(id) =>
      if raw_type == "response.output_item.done" ||
        (raw_type == "response.reasoning_summary_part.done" && !self.store) {
        None
      } else {
        Some(
          @provider.V4ReasoningEnd(
            id~,
            provider_metadata=self.reasoning_metadata(
              openai_v4_stream_item_id(id),
              false,
            ),
          ),
        )
      }
    @provider.ToolInputStart(id~, tool_name~) =>
      Some(
        @provider.V4ToolInputStart(
          id~,
          tool_name~,
          provider_executed=self.tool_start_provider_executed(raw),
          dynamic=false,
          title=None,
          provider_metadata=Map([]),
        ),
      )
    @provider.ToolInputDelta(id~, delta~) =>
      Some(@provider.V4ToolInputDelta(id~, delta~, provider_metadata=Map([])))
    @provider.ToolInputEnd(id) =>
      Some(
        @provider.V4ToolInputEnd(
          id~,
          provider_metadata=self.tool_input_end_metadata(raw),
        ),
      )
    @provider.ToolCallReady(value) =>
      Some(
        @provider.V4ToolCallReady(
          @provider.LanguageModelV4ToolCall::from_tool_call(value),
        ),
      )
    @provider.ToolResultReady(value) =>
      Some(
        @provider.V4ToolResultReady(
          @provider.LanguageModelV4ToolResult::from_tool_result(value),
        ),
      )
    @provider.ToolApprovalRequestReady(value) =>
      Some(
        @provider.V4ToolApprovalRequestReady(
          @provider.LanguageModelV4ToolApprovalRequest::from_tool_approval_request(
            value,
          ),
        ),
      )
    @provider.FileReady(value) =>
      Some(
        @provider.V4FileReady(
          @provider.LanguageModelV4File::from_generated_file(value),
        ),
      )
    @provider.ReasoningFileReady(value) =>
      Some(
        @provider.V4ReasoningFileReady(
          @provider.LanguageModelV4ReasoningFile::from_generated_file(value),
        ),
      )
    @provider.SourceReady(value) =>
      Some(
        @provider.V4SourceReady(
          @provider.LanguageModelV4Source::from_generated_source(value),
        ),
      )
    @provider.CustomContentReady(value) =>
      Some(
        @provider.V4CustomContentReady({
          kind: value.kind,
          provider_metadata: @provider.copy_provider_metadata(
            value.provider_metadata,
          ),
        }),
      )
    @provider.ResponseMetadataReady(value) =>
      Some(@provider.V4ResponseMetadataReady(value))
    @provider.Finish(usage~, reason~) =>
      Some(
        @provider.V4Finish(
          usage=@provider.LanguageModelV4Usage::from_usage(usage),
          reason=@provider.LanguageModelV4FinishReason::from_finish_reason(
            reason,
          ),
          provider_metadata=Map([]),
        ),
      )
    @provider.Raw(value) => Some(@provider.V4Raw(value))
    @provider.StreamError(message) => Some(@provider.V4Error(message))
  }
}

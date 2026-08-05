///|
priv struct OpenAIResponsesHostedStreamDecoder {
  provider_name : String
  tool_name_mapping : @provider_utils.ToolNameMapping
  id_generator : @provider_utils.IdGenerator
  items : Array[Json?]
  hosted_item_ids : Array[String]
  hosted_kinds : Array[String]
  hosted_call_ids : Array[String]
  hosted_names : Array[String]
  hosted_container_ids : Array[String]
  hosted_input_delta : Array[Bool]
  hosted_input_end : Array[Bool]
  hosted_diff_seen : Array[Bool]
  hosted_code_delta_seen : Array[Bool]
  hosted_ready : Array[Bool]
  mut response_output : Array[Json]
  mut has_response_output : Bool
}

///|
fn OpenAIResponsesHostedStreamDecoder::new(
  provider_name : String,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  id_generator~ : @provider_utils.IdGenerator,
) -> OpenAIResponsesHostedStreamDecoder {
  {
    provider_name,
    tool_name_mapping,
    id_generator,
    items: [],
    hosted_item_ids: [],
    hosted_kinds: [],
    hosted_call_ids: [],
    hosted_names: [],
    hosted_container_ids: [],
    hosted_input_delta: [],
    hosted_input_end: [],
    hosted_diff_seen: [],
    hosted_code_delta_seen: [],
    hosted_ready: [],
    response_output: [],
    has_response_output: false,
  }
}

///|
fn OpenAIResponsesHostedStreamDecoder::custom_tool_name(
  self : OpenAIResponsesHostedStreamDecoder,
  provider_tool_name : String,
) -> String {
  self.tool_name_mapping.to_custom_tool_name(provider_tool_name)
}

///|
fn OpenAIResponsesHostedStreamDecoder::store_item(
  self : OpenAIResponsesHostedStreamDecoder,
  item : Json,
  output_index : Int,
) -> Unit {
  let index = if output_index < 0 { self.items.length() } else { output_index }
  while self.items.length() <= index {
    self.items.push(None)
  }
  self.items[index] = Some(item)
}

///|
fn OpenAIResponsesHostedStreamDecoder::find_hosted_item(
  self : OpenAIResponsesHostedStreamDecoder,
  item_id : String,
) -> Int? {
  for index, value in self.hosted_item_ids {
    if value == item_id {
      return Some(index)
    }
  }
  None
}

///|
/// Return the state slot for one output item, growing sparse output indexes as
/// needed. Hosted Responses events use output indexes while final items are
/// identified by their item id, so both forms are retained.
fn OpenAIResponsesHostedStreamDecoder::ensure_hosted_item(
  self : OpenAIResponsesHostedStreamDecoder,
  output_index : Int,
  item_id : String,
) -> Int {
  let index = if output_index >= 0 {
    output_index
  } else {
    self.find_hosted_item(item_id).unwrap_or(self.hosted_item_ids.length())
  }
  while self.hosted_item_ids.length() <= index {
    self.hosted_item_ids.push("")
    self.hosted_kinds.push("")
    self.hosted_call_ids.push("")
    self.hosted_names.push("")
    self.hosted_container_ids.push("")
    self.hosted_input_delta.push(false)
    self.hosted_input_end.push(false)
    self.hosted_diff_seen.push(false)
    self.hosted_code_delta_seen.push(false)
    self.hosted_ready.push(false)
  }
  if item_id != "" {
    self.hosted_item_ids[index] = item_id
  }
  index
}

///|
/// Escape a string fragment that is being appended inside a JSON string.
fn openai_escape_json_delta(value : String) -> String {
  let encoded = Json::string(value).stringify()
  if encoded.length() >= 2 {
    encoded[1:encoded.length() - 1].to_owned()
  } else {
    encoded
  }
}

///|
fn openai_hosted_item_type(item : Json) -> String {
  @provider_utils.json_string_field(item, "type").unwrap_or("")
}

///|
fn openai_hosted_item_id(item : Json) -> String {
  @provider_utils.json_string_field(item, "id").unwrap_or("item-0")
}

///|
fn openai_hosted_call_id(item : Json) -> String {
  @provider_utils.json_string_field(item, "call_id").unwrap_or(
    openai_hosted_item_id(item),
  )
}

///|
fn openai_hosted_output_index(json : Json) -> Int {
  match json {
    { "output_index": Number(value, ..), .. } => value.to_int()
    _ => -1
  }
}

///|
fn OpenAIResponsesHostedStreamDecoder::hosted_generated_parts(
  self : OpenAIResponsesHostedStreamDecoder,
  item : Json,
) -> Array[@provider.GeneratedContent] {
  let (parts, _) = openai_responses_output_content(
    [item],
    self.provider_name,
    self.tool_name_mapping,
    self.id_generator,
  )
  parts
}

///|
fn OpenAIResponsesHostedStreamDecoder::emit_parts(
  self : OpenAIResponsesHostedStreamDecoder,
  item : Json,
  events : Array[@provider.StreamEvent],
  emit_call : Bool,
  emit_result : Bool,
  emit_input_end : Bool,
) -> Unit {
  for part in self.hosted_generated_parts(item) {
    match part {
      @provider.GeneratedToolCallOutput(call) => {
        if emit_input_end {
          events.push(@provider.ToolInputEnd(call.id))
        }
        if emit_call {
          events.push(@provider.ToolCallReady(call))
        }
      }
      @provider.GeneratedToolResultOutput(result) if emit_result =>
        events.push(@provider.ToolResultReady(result))
      @provider.GeneratedToolApprovalRequestOutput(approval) if emit_result =>
        events.push(@provider.ToolApprovalRequestReady(approval))
      @provider.GeneratedCustomOutput(custom) if emit_result =>
        events.push(@provider.CustomContentReady(custom))
      _ => ()
    }
  }
}

///|
fn OpenAIResponsesHostedStreamDecoder::added_events(
  self : OpenAIResponsesHostedStreamDecoder,
  item : Json,
  output_index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let kind = openai_hosted_item_type(item)
  let item_id = openai_hosted_item_id(item)
  if kind == "web_search_call" {
    events.push(
      @provider.ToolInputStart(
        id=item_id,
        tool_name=self.custom_tool_name("web_search"),
      ),
    )
    events.push(@provider.ToolInputEnd(item_id))
    events.push(
      @provider.ToolCallReady(
        openai_responses_tool_call(
          item_id,
          self.custom_tool_name("web_search"),
          "{}",
          self.provider_name,
          item_id,
          provider_executed=true,
        ),
      ),
    )
  } else if kind == "file_search_call" {
    events.push(
      @provider.ToolCallReady(
        openai_responses_tool_call(
          item_id,
          self.custom_tool_name("file_search"),
          "{}",
          self.provider_name,
          item_id,
          provider_executed=true,
        ),
      ),
    )
  } else if kind == "image_generation_call" {
    events.push(
      @provider.ToolCallReady(
        openai_responses_tool_call(
          item_id,
          self.custom_tool_name("image_generation"),
          "{}",
          self.provider_name,
          item_id,
          provider_executed=true,
        ),
      ),
    )
  } else if kind == "code_interpreter_call" {
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = kind
    self.hosted_call_ids[state] = item_id
    self.hosted_container_ids[state] = @provider_utils.json_string_field(
      item, "container_id",
    ).unwrap_or("")
    events.push(
      @provider.ToolInputStart(
        id=item_id,
        tool_name=self.custom_tool_name("code_interpreter"),
      ),
    )
    events.push(
      @provider.ToolInputDelta(
        id=item_id,
        delta="{\"containerId\":\"\{openai_escape_json_delta(self.hosted_container_ids[state])}\",\"code\":\"",
      ),
    )
    self.hosted_input_delta[state] = true
  } else if kind == "computer_call" {
    let call_id = openai_hosted_call_id(item)
    events.push(
      @provider.ToolInputStart(
        id=call_id,
        tool_name=self.custom_tool_name("computer"),
      ),
    )
  } else if kind == "apply_patch_call" {
    let call_id = openai_hosted_call_id(item)
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = kind
    self.hosted_call_ids[state] = call_id
    let operation = match item {
      { "operation": value, .. } => value
      _ => Json::object(Map([]))
    }
    let operation_type = @provider_utils.json_string_field(operation, "type").unwrap_or(
      "",
    )
    events.push(
      @provider.ToolInputStart(
        id=call_id,
        tool_name=self.custom_tool_name("apply_patch"),
      ),
    )
    if operation_type == "delete_file" {
      events.push(
        @provider.ToolInputDelta(
          id=call_id,
          delta=({ "callId": call_id, "operation": operation } : Json).stringify(),
        ),
      )
      events.push(@provider.ToolInputEnd(call_id))
      self.hosted_input_delta[state] = true
      self.hosted_input_end[state] = true
    } else {
      let path = @provider_utils.json_string_field(operation, "path").unwrap_or(
        "",
      )
      events.push(
        @provider.ToolInputDelta(
          id=call_id,
          delta="{\"callId\":\"\{openai_escape_json_delta(call_id)}\",\"operation\":{\"type\":\"\{openai_escape_json_delta(operation_type)}\",\"path\":\"\{openai_escape_json_delta(path)}\",\"diff\":\"",
        ),
      )
      self.hosted_input_delta[state] = true
    }
  } else if kind == "custom_tool_call" {
    let call_id = openai_hosted_call_id(item)
    let name = @provider_utils.json_string_field(item, "name").unwrap_or(
      "custom",
    )
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = kind
    self.hosted_call_ids[state] = call_id
    self.hosted_names[state] = name
    events.push(
      @provider.ToolInputStart(
        id=call_id,
        tool_name=self.custom_tool_name(name),
      ),
    )
  } else if kind == "tool_search_call" &&
    @provider_utils.json_string_field(item, "execution").unwrap_or("server") ==
    "server" {
    events.push(
      @provider.ToolInputStart(
        id=item_id,
        tool_name=self.custom_tool_name("tool_search"),
      ),
    )
  }
}

///|
fn OpenAIResponsesHostedStreamDecoder::done_events(
  self : OpenAIResponsesHostedStreamDecoder,
  item : Json,
  output_index : Int,
  events : Array[@provider.StreamEvent],
) -> Unit {
  let kind = openai_hosted_item_type(item)
  if kind == "function_call" || kind == "message" || kind == "reasoning" {
    return
  }
  if kind == "file_search_call" ||
    kind == "image_generation_call" ||
    kind == "web_search_call" {
    self.emit_parts(item, events, false, true, false)
  } else if kind == "code_interpreter_call" {
    let call_id = openai_hosted_item_id(item)
    let state = self.ensure_hosted_item(output_index, call_id)
    if self.hosted_kinds[state] == "" {
      self.hosted_kinds[state] = kind
      self.hosted_call_ids[state] = call_id
      self.hosted_container_ids[state] = @provider_utils.json_string_field(
        item, "container_id",
      ).unwrap_or("")
      events.push(
        @provider.ToolInputStart(
          id=call_id,
          tool_name=self.custom_tool_name("code_interpreter"),
        ),
      )
      events.push(
        @provider.ToolInputDelta(
          id=call_id,
          delta="{\"containerId\":\"\{openai_escape_json_delta(self.hosted_container_ids[state])}\",\"code\":\"",
        ),
      )
      self.hosted_input_delta[state] = true
    }
    if !self.hosted_input_end[state] {
      if !self.hosted_code_delta_seen[state] {
        let code = @provider_utils.json_string_field(item, "code").unwrap_or("")
        if code != "" {
          events.push(
            @provider.ToolInputDelta(
              id=call_id,
              delta=openai_escape_json_delta(code),
            ),
          )
        }
      }
      events.push(@provider.ToolInputDelta(id=call_id, delta="\"}"))
      events.push(@provider.ToolInputEnd(call_id))
      self.hosted_input_end[state] = true
    }
    for part in self.hosted_generated_parts(item) {
      match part {
        @provider.GeneratedToolCallOutput(call) if !self.hosted_ready[state] => {
          events.push(@provider.ToolCallReady(call))
          self.hosted_ready[state] = true
        }
        @provider.GeneratedToolResultOutput(result) =>
          events.push(@provider.ToolResultReady(result))
        _ => ()
      }
    }
  } else if kind == "computer_call" {
    self.emit_parts(item, events, true, true, true)
  } else if kind == "apply_patch_call" {
    let call_id = openai_hosted_call_id(item)
    let state = self.ensure_hosted_item(
      output_index,
      openai_hosted_item_id(item),
    )
    self.hosted_kinds[state] = kind
    self.hosted_call_ids[state] = call_id
    if !self.hosted_input_end[state] {
      let operation = match item {
        { "operation": value, .. } => value
        _ => Json::object(Map([]))
      }
      if !self.hosted_diff_seen[state] {
        match @provider_utils.json_string_field(operation, "diff") {
          Some(diff) if diff != "" => {
            events.push(
              @provider.ToolInputDelta(
                id=call_id,
                delta=openai_escape_json_delta(diff),
              ),
            )
            self.hosted_diff_seen[state] = true
          }
          _ => ()
        }
      }
      events.push(@provider.ToolInputDelta(id=call_id, delta="\"}}"))
      events.push(@provider.ToolInputEnd(call_id))
      self.hosted_input_end[state] = true
    }
    if @provider_utils.json_string_field(item, "status").unwrap_or("") ==
      "completed" &&
      !self.hosted_ready[state] {
      for part in self.hosted_generated_parts(item) {
        match part {
          @provider.GeneratedToolCallOutput(call) => {
            events.push(@provider.ToolCallReady(call))
            self.hosted_ready[state] = true
          }
          _ => ()
        }
      }
    }
  } else if kind == "custom_tool_call" {
    let item_id = openai_hosted_item_id(item)
    let call_id = openai_hosted_call_id(item)
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = kind
    self.hosted_call_ids[state] = call_id
    if !self.hosted_input_end[state] {
      if !self.hosted_input_delta[state] {
        match item {
          { "input": input, .. } => {
            let input = openai_responses_string_or_json(input)
            if input != "" {
              events.push(@provider.ToolInputDelta(id=call_id, delta=input))
            }
          }
          _ => ()
        }
      }
      events.push(@provider.ToolInputEnd(call_id))
      self.hosted_input_end[state] = true
    }
    if !self.hosted_ready[state] {
      self.emit_parts(item, events, true, false, false)
      self.hosted_ready[state] = true
    }
  } else if kind == "local_shell_call" || kind == "shell_call" {
    let call_id = openai_hosted_call_id(item)
    let name = if kind == "local_shell_call" { "local_shell" } else { "shell" }
    if kind == "local_shell_call" || kind == "shell_call" {
      events.push(
        @provider.ToolInputStart(
          id=call_id,
          tool_name=self.custom_tool_name(name),
        ),
      )
    }
    self.emit_parts(item, events, true, false, true)
  } else if kind == "shell_call_output" {
    self.emit_parts(item, events, false, true, false)
  } else if kind == "program" {
    self.emit_parts(item, events, true, false, false)
  } else if kind == "program_output" {
    self.emit_parts(item, events, false, true, false)
  } else if kind == "tool_search_call" {
    self.emit_parts(item, events, true, false, true)
  } else if kind == "tool_search_output" {
    self.emit_parts(item, events, false, true, false)
  } else if kind == "mcp_call" {
    self.emit_parts(item, events, true, true, false)
  } else if kind == "mcp_approval_request" {
    self.emit_parts(item, events, true, true, false)
  } else if kind == "compaction" {
    self.emit_parts(item, events, false, true, false)
  }
}

///|
fn OpenAIResponsesHostedStreamDecoder::observe(
  self : OpenAIResponsesHostedStreamDecoder,
  json : Json,
) -> Array[@provider.StreamEvent] {
  let events : Array[@provider.StreamEvent] = []
  let event_type = @provider_utils.json_string_field(json, "type").unwrap_or("")
  if event_type == "response.output_item.added" {
    match json {
      { "item": item, .. } => {
        let output_index = openai_hosted_output_index(json)
        self.store_item(item, output_index)
        self.added_events(item, output_index, events)
      }
      _ => ()
    }
  } else if event_type == "response.output_item.done" {
    match json {
      { "item": item, .. } => {
        let output_index = openai_hosted_output_index(json)
        self.store_item(item, output_index)
        self.done_events(item, output_index, events)
      }
      _ => ()
    }
  } else if event_type == "response.output_text.annotation.added" {
    match json {
      { "annotation": annotation, "item_id": String(item_id), .. } =>
        for
          source in openai_responses_source_contents(
            [annotation],
            self.provider_name,
            item_id,
            0,
            self.id_generator,
          ) {
          match source {
            @provider.GeneratedSourceOutput(value) =>
              events.push(@provider.SourceReady(value))
            _ => ()
          }
        }
      _ => ()
    }
  } else if event_type == "response.custom_tool_call_input.delta" {
    let output_index = openai_hosted_output_index(json)
    let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
      "tool-item-0",
    )
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = "custom_tool_call"
    let call_id = if self.hosted_call_ids[state] == "" {
      item_id
    } else {
      self.hosted_call_ids[state]
    }
    self.hosted_call_ids[state] = call_id
    let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
    if delta != "" {
      events.push(@provider.ToolInputDelta(id=call_id, delta~))
      self.hosted_input_delta[state] = true
    }
  } else if event_type == "response.apply_patch_call_operation_diff.delta" {
    let output_index = openai_hosted_output_index(json)
    let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
      "apply-patch-item-0",
    )
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = "apply_patch_call"
    let call_id = if self.hosted_call_ids[state] == "" {
      item_id
    } else {
      self.hosted_call_ids[state]
    }
    self.hosted_call_ids[state] = call_id
    if !self.hosted_input_end[state] {
      let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
      if delta != "" {
        events.push(
          @provider.ToolInputDelta(
            id=call_id,
            delta=openai_escape_json_delta(delta),
          ),
        )
        self.hosted_input_delta[state] = true
        self.hosted_diff_seen[state] = true
      }
    }
  } else if event_type == "response.apply_patch_call_operation_diff.done" {
    let output_index = openai_hosted_output_index(json)
    let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
      "apply-patch-item-0",
    )
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = "apply_patch_call"
    let call_id = if self.hosted_call_ids[state] == "" {
      item_id
    } else {
      self.hosted_call_ids[state]
    }
    self.hosted_call_ids[state] = call_id
    if !self.hosted_input_end[state] {
      if !self.hosted_diff_seen[state] {
        let diff = @provider_utils.json_string_field(json, "diff").unwrap_or("")
        if diff != "" {
          events.push(
            @provider.ToolInputDelta(
              id=call_id,
              delta=openai_escape_json_delta(diff),
            ),
          )
          self.hosted_diff_seen[state] = true
        }
      }
      events.push(@provider.ToolInputDelta(id=call_id, delta="\"}}"))
      events.push(@provider.ToolInputEnd(call_id))
      self.hosted_input_end[state] = true
    }
  } else if event_type == "response.code_interpreter_call_code.delta" {
    let output_index = openai_hosted_output_index(json)
    let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
      "code-interpreter-item-0",
    )
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = "code_interpreter_call"
    let call_id = if self.hosted_call_ids[state] == "" {
      item_id
    } else {
      self.hosted_call_ids[state]
    }
    self.hosted_call_ids[state] = call_id
    let delta = @provider_utils.json_string_field(json, "delta").unwrap_or("")
    if !self.hosted_input_end[state] && delta != "" {
      events.push(
        @provider.ToolInputDelta(
          id=call_id,
          delta=openai_escape_json_delta(delta),
        ),
      )
      self.hosted_input_delta[state] = true
      self.hosted_code_delta_seen[state] = true
    }
  } else if event_type == "response.code_interpreter_call_code.done" {
    let output_index = openai_hosted_output_index(json)
    let item_id = @provider_utils.json_string_field(json, "item_id").unwrap_or(
      "code-interpreter-item-0",
    )
    let state = self.ensure_hosted_item(output_index, item_id)
    self.hosted_kinds[state] = "code_interpreter_call"
    let call_id = if self.hosted_call_ids[state] == "" {
      item_id
    } else {
      self.hosted_call_ids[state]
    }
    self.hosted_call_ids[state] = call_id
    let code = @provider_utils.json_string_field(json, "code").unwrap_or("")
    if !self.hosted_input_end[state] {
      if !self.hosted_code_delta_seen[state] && code != "" {
        events.push(
          @provider.ToolInputDelta(
            id=call_id,
            delta=openai_escape_json_delta(code),
          ),
        )
      }
      events.push(@provider.ToolInputDelta(id=call_id, delta="\"}"))
      events.push(@provider.ToolInputEnd(call_id))
      self.hosted_input_end[state] = true
    }
    if !self.hosted_ready[state] {
      let container_id = self.hosted_container_ids[state]
      let call = openai_responses_tool_call(
        call_id,
        self.custom_tool_name("code_interpreter"),
        ({ "code": code, "containerId": container_id } : Json).stringify(),
        self.provider_name,
        item_id,
        provider_executed=true,
      )
      events.push(@provider.ToolCallReady(call))
      self.hosted_ready[state] = true
    }
  } else if event_type == "response.image_generation_call.partial_image" {
    match json {
      { "item_id": String(item_id), "partial_image_b64": String(value), .. } =>
        events.push(
          @provider.ToolResultReady(
            openai_responses_tool_result(
              item_id,
              self.custom_tool_name("image_generation"),
              { "result": value },
              self.provider_name,
              item_id,
              preliminary=true,
            ),
          ),
        )
      _ => ()
    }
  } else if event_type == "response.completed" ||
    event_type == "response.incomplete" {
    match json {
      { "response": { "output": Array(items), .. }, .. } => {
        self.response_output = items
        self.has_response_output = true
      }
      _ => ()
    }
  }
  events
}

///|
fn OpenAIResponsesHostedStreamDecoder::content(
  self : OpenAIResponsesHostedStreamDecoder,
) -> Array[@provider.GeneratedContent] {
  if self.has_response_output {
    let (content, _) = openai_responses_output_content(
      self.response_output,
      self.provider_name,
      self.tool_name_mapping,
      self.id_generator,
    )
    return content
  }
  let items : Array[Json] = []
  for item in self.items {
    if item is Some(value) {
      items.push(value)
    }
  }
  let (content, _) = openai_responses_output_content(
    items,
    self.provider_name,
    self.tool_name_mapping,
    self.id_generator,
  )
  content
}

///|
fn OpenAIResponsesHostedStreamDecoder::has_client_calls(
  self : OpenAIResponsesHostedStreamDecoder,
) -> Bool {
  let values = if self.has_response_output {
    self.response_output
  } else {
    let result : Array[Json] = []
    for item in self.items {
      if item is Some(value) {
        result.push(value)
      }
    }
    result
  }
  for item in values {
    let kind = openai_hosted_item_type(item)
    if kind == "function_call" ||
      kind == "custom_tool_call" ||
      kind == "apply_patch_call" ||
      kind == "local_shell_call" ||
      kind == "shell_call" {
      return true
    }
    if kind == "tool_search_call" &&
      @provider_utils.json_string_field(item, "execution").unwrap_or("server") !=
      "server" {
      return true
    }
    if kind == "computer_call" &&
      @provider_utils.json_string_field(item, "call_id") is Some(_) {
      return true
    }
  }
  false
}

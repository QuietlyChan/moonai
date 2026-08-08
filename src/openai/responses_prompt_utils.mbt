///|
fn openai_input_text(text : String) -> Json {
  { "type": "input_text", "text": text }
}

///|
fn openai_output_text(text : String) -> Json {
  { "type": "output_text", "text": text }
}

///|
fn openai_responses_image_fields(
  image_url : String,
  options : Map[String, Json],
  provider_name : String,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([
    ("type", Json::string("input_image")),
    ("image_url", Json::string(image_url)),
  ])
  if openai_responses_prompt_option(options, provider_name, "imageDetail")
    is Some(String(detail)) {
    fields["detail"] = Json::string(detail)
  }
  fields
}

///|
fn with_openai_responses_prompt_options(
  content : Json,
  options : Map[String, Json],
  provider_name : String,
) -> Json {
  guard content is Object(fields) else { return content }
  guard openai_responses_prompt_option(
      options, provider_name, "promptCacheBreakpoint",
    )
    is Some(breakpoint) else {
    return content
  }
  let result = @provider.copy_provider_metadata(fields)
  result["prompt_cache_breakpoint"] = breakpoint
  Json::object(result)
}

///|
fn openai_message_item(role : String, content : Json) -> Json {
  Json::object(Map([("role", Json::string(role)), ("content", content)]))
}

///|
fn openai_responses_prompt_option(
  options : Map[String, Json],
  provider_name : String,
  field : String,
) -> Json? {
  let provider_key = openai_responses_provider_metadata_key(provider_name)
  match options.get(provider_key) {
    Some(Object(values)) =>
      match values.get(field) {
        Some(Null) | None => None
        Some(value) => Some(value)
      }
    _ => None
  }
}

///|
fn openai_responses_string_option(
  options : Map[String, Json],
  field : String,
  fallback_field : String,
  provider_name : String,
) -> String? {
  let value = match
    openai_responses_prompt_option(options, provider_name, field) {
    Some(value) => Some(value)
    None =>
      openai_responses_prompt_option(options, provider_name, fallback_field)
  }
  match value {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
/// Read a boolean flag attached to a prompt part/message in the OpenAI
/// provider namespace. Both camelCase and snake_case are accepted so decoded
/// metadata can be fed back into a request without a manual rewrite.
fn openai_responses_bool_option(
  options : Map[String, Json],
  field : String,
  fallback_field : String,
  provider_name : String,
) -> Bool {
  let value = match
    openai_responses_prompt_option(options, provider_name, field) {
    Some(value) => Some(value)
    None =>
      openai_responses_prompt_option(options, provider_name, fallback_field)
  }
  match value {
    Some(True) => true
    _ => false
  }
}

///|
/// Map provider metadata for a Responses tool caller back to wire form.
fn openai_responses_tool_caller_wire(value : Json) -> Json? {
  match value {
    { "type": "direct", .. } => Some({ "type": "direct" })
    { "type": "program", "callerId": String(caller_id), .. } =>
      Some({ "type": "program", "caller_id": caller_id })
    { "type": "program", "caller_id": String(caller_id), .. } =>
      Some({ "type": "program", "caller_id": caller_id })
    _ => None
  }
}

///|
/// Tool capabilities that affect how prior Responses output items must be
/// replayed. This mirrors the information passed from AI SDK's Responses tool
/// preparation step into its prompt converter.
priv struct OpenAIResponsesToolCapabilities {
  has_local_shell : Bool
  has_shell : Bool
  has_apply_patch : Bool
  has_computer : Bool
  custom_tool_names : Map[String, Bool]
}

///|
fn OpenAIResponsesToolCapabilities::is_custom_tool(
  self : OpenAIResponsesToolCapabilities,
  name : String,
) -> Bool {
  self.custom_tool_names.get(name) is Some(true)
}

///|
fn OpenAIResponsesToolCapabilities::is_stored_provider_tool(
  self : OpenAIResponsesToolCapabilities,
  name : String,
) -> Bool {
  (self.has_local_shell && name == "local_shell") ||
  (self.has_shell && name == "shell") ||
  (self.has_apply_patch && name == "apply_patch") ||
  (self.has_computer && name == "computer") ||
  self.is_custom_tool(name)
}

///|
/// Add one assistant reasoning part to Responses input. OpenAI groups summary
/// parts by item id and stores the encrypted payload on the final part.
fn append_openai_reasoning_part(
  reasoning_text : String,
  provider_options : Map[String, Json],
  input : Array[Json],
  warnings : Array[@provider.Warning],
  store : Bool,
  has_conversation : Bool,
  has_previous_response_id : Bool,
  reasoning_item_indices : Map[String, Int],
  reasoning_references : Map[String, Bool],
  reasoning_items_with_encrypted_content : Map[String, Bool],
  provider_name : String,
) -> Unit {
  let item_id = openai_responses_string_option(
    provider_options, "itemId", "item_id", provider_name,
  )
  let encrypted_content = openai_responses_string_option(
    provider_options, "reasoningEncryptedContent", "reasoning_encrypted_content",
    provider_name,
  )
  if (has_conversation || has_previous_response_id) && item_id is Some(_) {
    return
  }
  match item_id {
    Some(id) if store =>
      if reasoning_references.get(id) is None {
        input.push({ "type": "item_reference", "id": id })
        reasoning_references[id] = true
      }
    Some(id) => {
      let summary : Array[Json] = if reasoning_text == "" {
        []
      } else {
        [{ "type": "summary_text", "text": reasoning_text }]
      }
      match reasoning_item_indices.get(id) {
        Some(index) =>
          match input[index] {
            Object(fields) => {
              let updated = @provider.copy_provider_metadata(fields)
              if summary.length() > 0 {
                let existing : Array[Json] = match updated.get("summary") {
                  Some(Array(values)) => values.copy()
                  _ => []
                }
                for part in summary {
                  existing.push(part)
                }
                updated["summary"] = Json::array(existing)
              }
              if encrypted_content is Some(value) {
                updated["encrypted_content"] = Json::string(value)
                reasoning_items_with_encrypted_content[id] = true
              }
              input[index] = Json::object(updated)
            }
            _ => ()
          }
        None => {
          let fields : Map[String, Json] = Map(
            [
              ("type", Json::string("reasoning")),
              ("id", Json::string(id)),
              ("summary", Json::array(summary)),
              ..if encrypted_content is Some(value) {
                [("encrypted_content", Json::string(value))]
              },
            ],
          )
          reasoning_item_indices[id] = input.length()
          reasoning_items_with_encrypted_content[id] = encrypted_content
            is Some(_)
          input.push(Json::object(fields))
        }
      }
    }
    None =>
      match encrypted_content {
        Some(value) => {
          let summary : Array[Json] = if reasoning_text == "" {
            []
          } else {
            [{ "type": "summary_text", "text": reasoning_text }]
          }
          input.push({
            "type": "reasoning",
            "encrypted_content": value,
            "summary": Json::array(summary),
          })
        }
        None =>
          warnings.push(
            @provider.Warning::Other(
              message="Reasoning parts without an OpenAI itemId or encrypted content were skipped.",
            ),
          )
      }
  }
}

///|
/// OpenAI requires encrypted content when reasoning history is sent without
/// server-side storage. Delay this check until all parts have been merged,
/// because only the final part commonly carries the encrypted payload.
fn finalize_openai_reasoning_input(
  input : Array[Json],
  warnings : Array[@provider.Warning],
  reasoning_items_with_encrypted_content : Map[String, Bool],
) -> Array[Json] {
  let result : Array[Json] = []
  let mut skipped = false
  for item in input {
    let should_skip = match item {
      { "type": "reasoning", "id": String(id), .. } =>
        reasoning_items_with_encrypted_content.get(id) is Some(false)
      _ => false
    }
    if should_skip {
      skipped = true
    } else {
      result.push(item)
    }
  }
  if skipped {
    warnings.push(
      @provider.Warning::Other(
        message="Reasoning parts without encrypted content are not supported when store is false; they were skipped.",
      ),
    )
  }
  result
}

///|
/// Replay an OpenAI Responses compaction item from assistant history. Stored
/// items can be referenced directly; non-stored requests need the encrypted
/// compaction state to be sent back in full.
fn append_openai_compaction_input(
  provider_options : Map[String, Json],
  input : Array[Json],
  store : Bool,
  has_conversation : Bool,
  provider_name : String,
) -> Unit {
  let item_id = openai_responses_string_option(
    provider_options, "itemId", "item_id", provider_name,
  )
  guard item_id is Some(id) else { return }
  guard !has_conversation else { return }
  if store {
    input.push({ "type": "item_reference", "id": id })
  } else {
    let encrypted_content = openai_responses_string_option(
      provider_options, "encryptedContent", "encrypted_content", provider_name,
    )
    let fields : Map[String, Json] = Map(
      [
        ("type", Json::string("compaction")),
        ("id", Json::string(id)),
        ..if encrypted_content is Some(value) {
          [("encrypted_content", Json::string(value))]
        },
      ],
    )
    input.push(Json::object(fields))
  }
}

///|
fn openai_responses_computer_action_wire(value : Json) -> Json raise {
  let normalized = decode_openai_computer_action(value).to_json()
  guard normalized is Object(fields) else {
    fail("OpenAI computer action encoding produced a non-object")
  }
  let result : Map[String, Json] = Map([])
  for entry in fields.iter2() {
    let (key, item) = entry
    match key {
      "scrollX" => result["scroll_x"] = item
      "scrollY" => result["scroll_y"] = item
      _ => result[key] = item
    }
  }
  Json::object(result)
}

///|
fn openai_responses_computer_output_wire(
  tool_call_id : String,
  content : String,
) -> Json raise {
  let value = @json.parse(content)
  let output = match value {
    { "output": Object(_) as output, .. } => output
    _ => fail("OpenAI computer tool output requires an output object")
  }
  guard @provider_utils.json_string_field(output, "type")
    is Some("computer_screenshot") else {
    fail("OpenAI computer tool output must be a computer_screenshot")
  }
  let image_url = @provider_utils.json_string_field(output, "imageUrl")
  let file_id = @provider_utils.json_string_field(output, "fileId")
  guard image_url is Some(_) || file_id is Some(_) else {
    fail("OpenAI computer screenshot requires imageUrl or fileId")
  }
  let output_fields : Map[String, Json] = Map([
    ("type", Json::string("computer_screenshot")),
  ])
  if image_url is Some(item) {
    output_fields["image_url"] = Json::string(item)
  }
  if file_id is Some(item) {
    output_fields["file_id"] = Json::string(item)
  }
  if @provider_utils.json_string_field(output, "detail") is Some(item) {
    guard item == "auto" ||
      item == "low" ||
      item == "high" ||
      item == "original" else {
      fail("Unsupported OpenAI computer screenshot detail '\{item}'")
    }
    output_fields["detail"] = Json::string(item)
  }
  let acknowledged_values = match value {
    { "acknowledgedSafetyChecks": Array(values), .. } => values
    _ => []
  }
  let acknowledged : Array[Json] = []
  for item in acknowledged_values {
    acknowledged.push(decode_openai_computer_safety_check(item).to_json())
  }
  let fields : Map[String, Json] = Map([
    ("type", Json::string("computer_call_output")),
    ("call_id", Json::string(tool_call_id)),
    ("output", Json::object(output_fields)),
  ])
  if acknowledged.length() > 0 {
    fields["acknowledged_safety_checks"] = Json::array(acknowledged)
  }
  Json::object(fields)
}

///|
fn openai_allowed_tools_choice(
  value : Json,
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Json? {
  match value {
    { "toolNames": Array(tool_names), "mode": String(mode), .. } => {
      let tools : Array[Json] = []
      for name in tool_names {
        if name is String(value) {
          tools.push({
            "type": "function",
            "name": tool_name_mapping.to_provider_tool_name(value),
          })
        }
      }
      if tools.length() > 0 && (mode == "auto" || mode == "required") {
        Some(({ "type": "allowed_tools", "mode": mode, "tools": tools } : Json))
      } else {
        None
      }
    }
    { "toolNames": Array(tool_names), .. } => {
      let tools : Array[Json] = []
      for name in tool_names {
        if name is String(value) {
          tools.push({
            "type": "function",
            "name": tool_name_mapping.to_provider_tool_name(value),
          })
        }
      }
      if tools.length() > 0 {
        Some(
          ({ "type": "allowed_tools", "mode": "auto", "tools": tools } : Json),
        )
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn append_openai_include(values : Array[String], value : String) -> Unit {
  for existing in values {
    if existing == value {
      return
    }
  }
  values.push(value)
}

///|
fn openai_context_management(values : Array[Json]) -> Json? {
  let mapped : Array[Json] = []
  for value in values {
    match value {
      { "type": "compaction", "compactThreshold": Number(threshold, ..), .. } =>
        mapped.push({ "type": "compaction", "compact_threshold": threshold })
      { "type": "compaction", "compact_threshold": Number(threshold, ..), .. } =>
        mapped.push({ "type": "compaction", "compact_threshold": threshold })
      _ => ()
    }
  }
  if mapped.length() > 0 {
    Some(Json::array(mapped))
  } else {
    None
  }
}

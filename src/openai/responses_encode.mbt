///|
fn openai_input_text(text : String) -> Json {
  { "type": "input_text", "text": text }
}

///|
fn openai_output_text(text : String) -> Json {
  { "type": "output_text", "text": text }
}

///|
fn openai_data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}

///|
fn openai_responses_image_fields(
  image_url : String,
  options : Map[String, Json],
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([
    ("type", Json::string("input_image")),
    ("image_url", Json::string(image_url)),
  ])
  if openai_image_detail(options) is Some(detail) {
    fields["detail"] = Json::string(detail)
  }
  fields
}

///|
fn with_openai_responses_prompt_options(
  content : Json,
  options : Map[String, Json],
) -> Json {
  guard content is Object(fields) else { return content }
  guard openai_prompt_cache_breakpoint(options) is Some(breakpoint) else {
    return content
  }
  let result = @provider.copy_provider_metadata(fields)
  result["prompt_cache_breakpoint"] = breakpoint
  Json::object(result)
}

///|
fn openai_user_part(
  part : @provider.LanguageModelContentPart,
  pass_through_unsupported_files : Bool,
  index : Int,
  provider_name : String,
) -> Json raise {
  let provider_options = part.provider_options()
  let content : Json = match part.without_provider_options() {
    @provider.Text(value) => openai_input_text(value)
    @provider.ImageUrl(url) =>
      Json::object(openai_responses_image_fields(url, provider_options))
    @provider.ImageData(data~, media_type~) =>
      Json::object(
        openai_responses_image_fields(
          openai_data_uri(
            @provider_utils.resolve_full_media_type(media_type, data),
            data,
          ),
          provider_options,
        ),
      )
    @provider.FileUrl(url~, media_type~, filename=_) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      if top_level == "image" {
        Json::object(openai_responses_image_fields(url, provider_options))
      } else {
        with_openai_responses_prompt_options(
          ({ "type": "input_file", "file_url": url } : Json),
          provider_options,
        )
      }
    }
    @provider.FileData(data~, media_type~, filename~) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      if top_level == "image" {
        Json::object(
          openai_responses_image_fields(
            openai_data_uri(full_media_type, data),
            provider_options,
          ),
        )
      } else {
        guard full_media_type == "application/pdf" ||
          pass_through_unsupported_files else {
          fail(
            "OpenAI Responses does not accept file media type \{full_media_type}",
          )
        }
        let resolved_filename = if filename != "" {
          filename
        } else if full_media_type == "application/pdf" {
          "part-\{index}.pdf"
        } else {
          "part-\{index}"
        }
        with_openai_responses_prompt_options(
          {
            "type": "input_file",
            "filename": resolved_filename,
            "file_data": openai_data_uri(full_media_type, data),
          },
          provider_options,
        )
      }
    }
    @provider.FileReference(reference~, media_type~, filename=_) => {
      let file_id = @provider_utils.resolve_provider_reference(
        reference,
        openai_provider_metadata_key(provider_name),
      )
      if @provider_utils.get_top_level_media_type(media_type) == "image" {
        let fields : Map[String, Json] = Map([
          ("type", Json::string("input_image")),
          ("file_id", Json::string(file_id)),
        ])
        if openai_image_detail(provider_options) is Some(detail) {
          fields["detail"] = Json::string(detail)
        }
        Json::object(fields)
      } else {
        with_openai_responses_prompt_options(
          ({ "type": "input_file", "file_id": file_id } : Json),
          provider_options,
        )
      }
    }
    @provider.AudioData(..) =>
      fail("OpenAI Responses does not accept audio content in this adapter")
    @provider.Reasoning(_)
    | @provider.ReasoningFileUrl(..)
    | @provider.ReasoningFileData(..)
    | @provider.Custom(..)
    | @provider.ToolCallPart(_)
    | @provider.ToolResultPart(_)
    | @provider.ToolApprovalRequestPart(_)
    | @provider.ToolApprovalResponsePart(_) =>
      fail(
        "OpenAI Responses does not accept this content part in a user message",
      )
    @provider.ProviderOptions(part~, ..) =>
      openai_user_part(
        part, pass_through_unsupported_files, index, provider_name,
      )
  }
  with_openai_responses_prompt_options(content, provider_options)
}

///|
fn openai_message_item(role : String, content : Json) -> Json {
  Json::object(Map([("role", Json::string(role)), ("content", content)]))
}

///|
fn openai_responses_string_option(
  options : Map[String, Json],
  field : String,
  fallback_field : String,
) -> String? {
  let value = match openai_prompt_option(options, field) {
    Some(value) => Some(value)
    None => openai_prompt_option(options, fallback_field)
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
) -> Bool {
  let value = match openai_prompt_option(options, field) {
    Some(value) => Some(value)
    None => openai_prompt_option(options, fallback_field)
  }
  match value {
    Some(True) => true
    _ => false
  }
}

///|
/// Add one assistant reasoning message to Responses input. Reasoning is kept
/// at the provider-neutral Message boundary for now; the OpenAI-specific
/// encrypted payload and item identity travel through provider options.
fn append_openai_reasoning_input(
  message : @provider.LanguageModelMessage,
  input : Array[Json],
  warnings : Array[@provider.Warning],
  store : Bool,
  has_conversation : Bool,
  has_previous_response_id : Bool,
  reasoning_item_indices : Map[String, Int],
  reasoning_references : Map[String, Bool],
) -> Unit {
  let reasoning_text = message.reasoning_content.unwrap_or("")
  let item_id = openai_responses_string_option(
    message.provider_options,
    "itemId",
    "item_id",
  )
  let encrypted_content = openai_responses_string_option(
    message.provider_options,
    "reasoningEncryptedContent",
    "reasoning_encrypted_content",
  )
  guard reasoning_text != "" ||
    item_id is Some(_) ||
    encrypted_content is Some(_) else {
    return
  }
  if has_conversation || has_previous_response_id {
    return
  }
  match item_id {
    Some(id) if store =>
      if reasoning_references.get(id) is None {
        input.push({ "type": "item_reference", "id": id })
        reasoning_references[id] = true
      }
    Some(id) => {
      if !store && encrypted_content is None {
        warnings.push(
          @provider.Warning::Other(
            message="Reasoning parts without encrypted content are not supported when store is false; they were skipped.",
          ),
        )
        return
      }
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
fn openai_responses_computer_call_wire(
  call : @provider.ToolCall,
  item_id : String,
) -> Json raise {
  let input = @json.parse(call.arguments)
  let actions = match input {
    { "actions": Array(values), .. } => values
    _ => fail("OpenAI computer tool input requires an actions array")
  }
  let mapped_actions : Array[Json] = []
  for action in actions {
    mapped_actions.push(openai_responses_computer_action_wire(action))
  }
  let pending_values = match input {
    { "pendingSafetyChecks": Array(values), .. } => values
    _ => fail("OpenAI computer tool input requires pendingSafetyChecks")
  }
  let pending_safety_checks : Array[Json] = []
  for value in pending_values {
    pending_safety_checks.push(
      decode_openai_computer_safety_check(value).to_json(),
    )
  }
  let status = @provider_utils.json_string_field(input, "status").unwrap_or_else(() => {
      fail("OpenAI computer tool input requires a status")
    },
  )
  guard status == "in_progress" ||
    status == "completed" ||
    status == "incomplete" else {
    fail("Unsupported OpenAI computer tool status '\{status}'")
  }
  {
    "type": "computer_call",
    "call_id": call.id,
    "id": item_id,
    "status": status,
    "actions": Json::array(mapped_actions),
    "pending_safety_checks": Json::array(pending_safety_checks),
  }
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
/// Convert one structured tool-result content item to the OpenAI Responses
/// input-content shape. Tool results use the same `input_*` content items as
/// user messages, but retain their own provider options and file references.
fn openai_responses_tool_result_content_part(
  part : @provider.LanguageModelToolResultContentPart,
  pass_through_unsupported_files : Bool,
  index : Int,
  provider_name : String,
) -> Json raise {
  match part {
    @provider.LanguageModelToolText(text~, provider_options~) =>
      openai_user_part(
        @provider.LanguageModelContentPart::text(text).with_provider_options(
          provider_options,
        ),
        pass_through_unsupported_files,
        index,
        provider_name,
      )
    @provider.LanguageModelToolFileUrl(
      url~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      openai_user_part(
        @provider.LanguageModelContentPart::file_url(
          url~,
          media_type~,
          filename~,
        ).with_provider_options(provider_options),
        pass_through_unsupported_files,
        index,
        provider_name,
      )
    @provider.LanguageModelToolFileData(
      data~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      openai_user_part(
        @provider.LanguageModelContentPart::file_data(
          data~,
          media_type~,
          filename~,
        ).with_provider_options(provider_options),
        pass_through_unsupported_files,
        index,
        provider_name,
      )
    @provider.LanguageModelToolFileReference(
      reference~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      openai_user_part(
        @provider.LanguageModelContentPart::file_reference(
          reference~,
          media_type~,
          filename~,
        ).with_provider_options(provider_options),
        pass_through_unsupported_files,
        index,
        provider_name,
      )
    @provider.LanguageModelToolCustom(..) =>
      fail("OpenAI Responses does not accept custom tool-result content")
  }
}

///|
/// Map the provider-neutral tool-result output to the Responses output value.
fn openai_responses_tool_result_output(
  output : @provider.LanguageModelToolResultOutput,
  pass_through_unsupported_files : Bool,
  provider_name : String,
) -> Json raise {
  match output {
    @provider.LanguageModelToolTextOutput(value~, ..)
    | @provider.LanguageModelToolErrorText(value~, ..) => Json::string(value)
    @provider.LanguageModelToolJsonOutput(value~, ..)
    | @provider.LanguageModelToolErrorJson(value~, ..) =>
      Json::string(value.stringify())
    @provider.LanguageModelToolExecutionDenied(reason~, ..) =>
      Json::string(reason.unwrap_or("Tool call execution denied."))
    @provider.LanguageModelToolContent(value~, ..) =>
      Json::array(
        [
          for index, part in value => {
            openai_responses_tool_result_content_part(
              part, pass_through_unsupported_files, index, provider_name,
            )
          }
        ],
      )
  }
}

///|
/// Encode a structured tool result as a Responses function-call output item.
fn openai_responses_tool_result_to_wire(
  result : @provider.LanguageModelToolResult,
  pass_through_unsupported_files : Bool,
  provider_name : String,
) -> Json raise {
  {
    "type": "function_call_output",
    "call_id": result.tool_call_id,
    "output": openai_responses_tool_result_output(
      result.output,
      pass_through_unsupported_files,
      provider_name,
    ),
  }
}

///|
/// Encode an approval response. The request item is referenced when the
/// response is sent through a stored Responses conversation.
fn openai_responses_tool_approval_response_to_wire(
  response : @provider.LanguageModelToolApprovalResponse,
  store : Bool,
  input : Array[Json],
  processed_approval_ids : Map[String, Bool],
) -> Unit {
  guard processed_approval_ids.get(response.approval_id) is None else { return }
  processed_approval_ids[response.approval_id] = true
  if store {
    input.push({ "type": "item_reference", "id": response.approval_id })
  }
  input.push({
    "type": "mcp_approval_response",
    "approval_request_id": response.approval_id,
    "approve": response.approved,
  })
}

///|
fn convert_to_openai_responses_input(
  messages : Array[@provider.LanguageModelMessage],
  system_message_mode : String,
  pass_through_unsupported_files : Bool,
  provider_name : String,
  store : Bool,
  has_conversation : Bool,
  has_previous_response_id : Bool,
  warnings : Array[@provider.Warning],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Array[Json] raise {
  let input : Array[Json] = []
  let reasoning_item_indices : Map[String, Int] = Map([])
  let reasoning_references : Map[String, Bool] = Map([])
  let provider_executed_tool_calls : Map[String, Bool] = Map([])
  let tool_call_names : Map[String, String] = Map([])
  let processed_approval_ids : Map[String, Bool] = Map([])
  for message in messages {
    match message.role {
      @provider.System =>
        if system_message_mode == "remove" {
          warnings.push(
            @provider.Warning::Other(
              message="system messages are removed for this model",
            ),
          )
        } else {
          let content = match
            openai_prompt_cache_breakpoint(message.provider_options) {
            Some(_) =>
              Json::array([
                with_openai_responses_prompt_options(
                  openai_input_text(message.content),
                  message.provider_options,
                ),
              ])
            None =>
              if message.parts.length() > 0 {
                let parts : Array[Json] = []
                for part in message.parts {
                  match part.without_provider_options() {
                    @provider.Text(value) =>
                      parts.push(
                        with_openai_responses_prompt_options(
                          openai_input_text(value),
                          part.provider_options(),
                        ),
                      )
                    _ => fail("OpenAI system messages support text only")
                  }
                }
                Json::array(parts)
              } else {
                Json::string(message.content)
              }
          }
          input.push(openai_message_item(system_message_mode, content))
        }
      @provider.User => {
        let content = if message.parts.length() > 0 {
          Json::array(
            [
              for index, part in message.parts => {
                openai_user_part(
                  part, pass_through_unsupported_files, index, provider_name,
                )
              }
            ],
          )
        } else {
          Json::array([openai_input_text(message.content)])
        }
        input.push(openai_message_item("user", content))
      }
      @provider.Assistant => {
        append_openai_reasoning_input(
          message, input, warnings, store, has_conversation, has_previous_response_id,
          reasoning_item_indices, reasoning_references,
        )
        let assistant_parts = if message.parts.length() > 0 {
          message.parts
        } else if message.content != "" {
          [@provider.LanguageModelContentPart::text(message.content)]
        } else {
          []
        }
        for part in assistant_parts {
          match part.without_provider_options() {
            @provider.Text(value) => {
              let part_options = part.provider_options()
              let item_id = match openai_prompt_option(part_options, "itemId") {
                Some(String(value)) => Some(value)
                _ => None
              }
              if (has_conversation || (has_previous_response_id && store)) &&
                item_id is Some(_) {
                continue
              }
              if store && item_id is Some(id) {
                input.push({ "type": "item_reference", "id": id })
              } else {
                let fields : Map[String, Json] = Map(
                  [
                    ("role", Json::string("assistant")),
                    (
                      "content",
                      Json::array([
                        with_openai_responses_prompt_options(
                          openai_output_text(value),
                          part_options,
                        ),
                      ]),
                    ),
                    ..if item_id is Some(id) {
                      [("id", Json::string(id))]
                    },
                    ..if openai_prompt_option(part_options, "phase")
                      is Some(String(phase)) {
                      [("phase", Json::string(phase))]
                    },
                  ],
                )
                input.push(Json::object(fields))
              }
            }
            @provider.ToolCallPart(_) => ()
            _ =>
              fail("OpenAI assistant messages support text content parts only")
          }
        }
        for call in message.effective_tool_calls() {
          let resolved_tool_name = tool_name_mapping.to_provider_tool_name(
            call.name,
          )
          tool_call_names[call.id] = resolved_tool_name
          let provider_key = openai_provider_metadata_key(provider_name)
          let item_id = match call.provider_metadata.get(provider_key) {
            Some(Object(values)) =>
              match values.get("itemId") {
                Some(String(value)) => Some(value)
                _ => None
              }
            _ => None
          }
          if (has_conversation || (has_previous_response_id && store)) &&
            item_id is Some(_) {
            continue
          }
          if call.provider_executed {
            provider_executed_tool_calls[call.id] = true
            if store && item_id is Some(id) {
              input.push({ "type": "item_reference", "id": id })
            }
            // Provider-executed calls are already represented by the
            // provider's output item. Re-sending them as function calls would
            // create a duplicate call when a response is continued.
            continue
          }
          if resolved_tool_name == "computer" {
            input.push(
              openai_responses_computer_call_wire(
                call,
                item_id.unwrap_or(call.id),
              ),
            )
            continue
          }
          let fields : Map[String, Json] = Map(
            [
              ("type", Json::string("function_call")),
              ("call_id", Json::string(call.id)),
              ("name", Json::string(resolved_tool_name)),
              ("arguments", Json::string(call.arguments)),
              ..if call.provider_metadata.get(provider_key)
                is Some(Object(values)) &&
                values.get("namespace") is Some(String(tool_namespace)) {
                [("namespace", Json::string(tool_namespace))]
              },
            ],
          )
          input.push(Json::object(fields))
        }
      }
      @provider.Tool(tool_call_id) => {
        let provider_options = message.provider_options
        let provider_executed = provider_executed_tool_calls.get(tool_call_id)
          is Some(_) ||
          openai_responses_bool_option(
            provider_options, "providerExecuted", "provider_executed",
          )
        let item_id = openai_responses_string_option(
          provider_options, "itemId", "item_id",
        )
        let resolved_item_id = item_id.unwrap_or(tool_call_id)
        if has_conversation {
          continue
        }
        let mut structured = false
        for part in message.parts {
          match part.without_provider_options() {
            @provider.ToolResultPart(result) => {
              structured = true
              let result_options = result.provider_options
              let approval_id = openai_responses_string_option(
                result_options, "approvalId", "approval_id",
              )
              // An approval denial is represented by the approval response
              // item and must not also become a function-call output.
              if result.output is @provider.LanguageModelToolExecutionDenied(..) &&
                approval_id is Some(_) {
                continue
              }
              let resolved_name = tool_name_mapping.to_provider_tool_name(
                result.tool_name,
              )
              let result_provider_executed = provider_executed_tool_calls.get(
                  result.tool_call_id,
                )
                is Some(_) ||
                openai_responses_bool_option(
                  result_options, "providerExecuted", "provider_executed",
                )
              if resolved_name == "computer" {
                input.push(
                  openai_responses_computer_output_wire(
                    result.tool_call_id,
                    result.output.to_json().stringify(),
                  ),
                )
              } else if result_provider_executed {
                let result_item_id = openai_responses_string_option(
                  result_options, "itemId", "item_id",
                ).unwrap_or(result.tool_call_id)
                if store {
                  input.push({ "type": "item_reference", "id": result_item_id })
                } else {
                  warnings.push(
                    @provider.Warning::Other(
                      message="Results for OpenAI provider-executed tools are not sent when store is false.",
                    ),
                  )
                }
              } else {
                input.push(
                  openai_responses_tool_result_to_wire(
                    result, pass_through_unsupported_files, provider_name,
                  ),
                )
              }
            }
            @provider.ToolApprovalResponsePart(response) => {
              structured = true
              openai_responses_tool_approval_response_to_wire(
                response, store, input, processed_approval_ids,
              )
            }
            _ => ()
          }
        }
        if structured {
          continue
        }
        if tool_call_names.get(tool_call_id) is Some("computer") {
          input.push(
            openai_responses_computer_output_wire(tool_call_id, message.content),
          )
          continue
        }
        if provider_executed {
          if store {
            input.push({ "type": "item_reference", "id": resolved_item_id })
          } else {
            warnings.push(
              @provider.Warning::Other(
                message="Results for OpenAI provider-executed tools are not sent when store is false.",
              ),
            )
          }
          continue
        }
        input.push({
          "type": "function_call_output",
          "call_id": tool_call_id,
          "output": if message.parts.length() > 0 {
            Json::array(
              [
                for index, part in message.parts => {
                  openai_user_part(
                    part, pass_through_unsupported_files, index, provider_name,
                  )
                }
              ],
            )
          } else {
            Json::string(message.content)
          },
        })
      }
    }
  }
  input
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
fn resolve_openai_responses_tool_choice(
  allowed_tools : Json?,
  choice : @provider.ToolChoice?,
  tools : Array[@provider.ToolDefinition],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Json? {
  match allowed_tools {
    Some(value) =>
      match openai_allowed_tools_choice(value, tool_name_mapping) {
        Some(resolved) => Some(resolved)
        None =>
          match choice {
            Some(resolved) =>
              Some(
                openai_responses_tool_choice(resolved, tools, tool_name_mapping),
              )
            None => None
          }
      }
    None =>
      match choice {
        Some(resolved) =>
          Some(openai_responses_tool_choice(resolved, tools, tool_name_mapping))
        None => None
      }
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
fn openai_text_config(
  response_format : @provider.ResponseFormat,
  strict_json_schema : Bool,
  verbosity : String?,
) -> Json? {
  let fields : Map[String, Json] = Map([])
  match response_format {
    @provider.Text => ()
    @provider.JsonResponse(config) =>
      match config.schema {
        None => fields["format"] = { "type": "json_object" }
        Some(schema) => {
          let format : Map[String, Json] = Map([
            ("type", Json::string("json_schema")),
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(strict_json_schema)),
          ])
          if config.description is Some(value) {
            format["description"] = Json::string(value)
          }
          fields["format"] = Json::object(format)
        }
      }
  }
  if verbosity is Some(value) {
    fields["verbosity"] = Json::string(value)
  }
  if fields.length() > 0 {
    Some(Json::object(fields))
  } else {
    None
  }
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

///|
fn prepare_openai_responses_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name : String,
  stream : Bool,
) -> OpenAIPreparedResponsesRequest raise {
  let parsed = parse_openai_responses_options(options, provider_name)
  let provider_options = parsed.options
  let warnings = parsed.warnings.copy()
  let tool_name_mapping = create_openai_tool_name_mapping(options.tools)
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="OpenAI Responses does not support topK.",
      ),
    )
  }
  let capabilities = get_openai_language_model_capabilities(model_id)
  if options.stop_sequences.length() > 0 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="stopSequences",
        details="OpenAI Responses does not support stop sequences.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="OpenAI Responses does not support seed.",
      ),
    )
  }
  if options.presence_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="presencePenalty",
        details="OpenAI Responses does not support presencePenalty.",
      ),
    )
  }
  if options.frequency_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="frequencyPenalty",
        details="OpenAI Responses does not support frequencyPenalty.",
      ),
    )
  }
  if provider_options.conversation is Some(_) &&
    provider_options.previous_response_id is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="conversation",
        details="conversation and previousResponseId cannot be used together.",
      ),
    )
  }
  let is_reasoning_model = provider_options.force_reasoning.unwrap_or(
    capabilities.is_reasoning_model,
  )
  let resolved_effort = match provider_options.reasoning_effort {
    Some(value) => Some(value)
    None => openai_reasoning_effort(options.reasoning_effort)
  }
  let resolved_summary = match provider_options.reasoning_summary {
    Some(value) => Some(value)
    None if resolved_effort is Some(value) && value != "none" =>
      Some("detailed")
    None => None
  }
  let system_message_mode = provider_options.system_message_mode.unwrap_or(
    if is_reasoning_model {
      "developer"
    } else {
      capabilities.system_message_mode
    },
  )
  let input = convert_to_openai_responses_input(
    options.messages,
    system_message_mode,
    provider_options.pass_through_unsupported_files,
    provider_name,
    provider_options.store.unwrap_or(true),
    provider_options.conversation is Some(_),
    provider_options.previous_response_id is Some(_),
    warnings,
    tool_name_mapping,
  )
  let tools = prepare_openai_responses_tools(options.tools, warnings)
  let mut temperature = options.temperature
  let mut top_p = options.top_p
  if is_reasoning_model {
    let allows_sampling = resolved_effort == Some("none") &&
      capabilities.supports_non_reasoning_parameters
    if !allows_sampling {
      if temperature is Some(_) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="temperature",
            details="temperature is not supported for reasoning models.",
          ),
        )
        temperature = None
      }
      if top_p is Some(_) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="topP",
            details="topP is not supported for reasoning models.",
          ),
        )
        top_p = None
      }
    }
  } else {
    if provider_options.reasoning_effort is Some(_) ||
      !(options.reasoning_effort is @provider.ProviderDefault) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningEffort",
          details="reasoningEffort is not supported for non-reasoning models.",
        ),
      )
    }
    if provider_options.reasoning_summary is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningSummary",
          details="reasoningSummary is not supported for non-reasoning models.",
        ),
      )
    }
    if provider_options.reasoning_mode is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningMode",
          details="reasoningMode is not supported for non-reasoning models.",
        ),
      )
    }
    if provider_options.reasoning_context is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoningContext",
          details="reasoningContext is not supported for non-reasoning models.",
        ),
      )
    }
  }
  let mut service_tier = provider_options.service_tier
  if service_tier == Some("flex") && !capabilities.supports_flex_processing {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="serviceTier",
        details="flex processing is not supported by this model.",
      ),
    )
    service_tier = None
  }
  if service_tier == Some("priority") &&
    !capabilities.supports_priority_processing {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="serviceTier",
        details="priority processing is not supported by this model.",
      ),
    )
    service_tier = None
  }
  let include_values = provider_options.include_values.copy()
  if provider_options.top_logprobs is Some(_) {
    append_openai_include(include_values, "message.output_text.logprobs")
  }
  if provider_options.store == Some(false) && is_reasoning_model {
    append_openai_include(include_values, "reasoning.encrypted_content")
  }
  for tool in options.tools {
    match tool {
      @provider.ProviderTool(id~, ..) if id == "openai.web_search" ||
        id == "openai.web_search_preview" =>
        append_openai_include(include_values, "web_search_call.action.sources")
      @provider.ProviderTool(id~, ..) if id == "openai.code_interpreter" =>
        append_openai_include(include_values, "code_interpreter_call.outputs")
      _ => ()
    }
  }
  let reasoning : Map[String, Json] = Map([])
  if is_reasoning_model {
    if resolved_effort is Some(value) {
      reasoning["effort"] = Json::string(value)
    }
    if resolved_summary is Some(value) {
      reasoning["summary"] = Json::string(value)
    }
    if provider_options.reasoning_mode is Some(value) {
      reasoning["mode"] = Json::string(value)
    }
    if provider_options.reasoning_context is Some(value) {
      reasoning["context"] = Json::string(value)
    }
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("input", Json::array(input)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if options.max_output_tokens is Some(value) {
        [("max_output_tokens", Json::number(value.to_double()))]
      },
      ..if temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if openai_text_config(
          options.response_format,
          provider_options.strict_json_schema,
          provider_options.text_verbosity,
        )
        is Some(value) {
        [("text", value)]
      },
      ..if provider_options.conversation is Some(value) {
        [("conversation", Json::string(value))]
      },
      ..if provider_options.max_tool_calls is Some(value) {
        [("max_tool_calls", Json::number(value.to_double()))]
      },
      ..if provider_options.metadata is Some(value) {
        [("metadata", value)]
      },
      ..if provider_options.parallel_tool_calls is Some(value) {
        [("parallel_tool_calls", Json::boolean(value))]
      },
      ..if provider_options.previous_response_id is Some(value) {
        [("previous_response_id", Json::string(value))]
      },
      ..if provider_options.store is Some(value) {
        [("store", Json::boolean(value))]
      },
      ..if provider_options.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if provider_options.instructions is Some(value) {
        [("instructions", Json::string(value))]
      },
      ..if service_tier is Some(value) {
        [("service_tier", Json::string(value))]
      },
      ..if include_values.length() > 0 {
        [
          (
            "include",
            Json::array([ for value in include_values => Json::string(value) ]),
          ),
        ]
      },
      ..if provider_options.prompt_cache_key is Some(value) {
        [("prompt_cache_key", Json::string(value))]
      },
      ..if provider_options.prompt_cache_options is Some(value) {
        [("prompt_cache_options", value)]
      },
      ..if provider_options.prompt_cache_retention is Some(value) {
        [("prompt_cache_retention", Json::string(value))]
      },
      ..if provider_options.safety_identifier is Some(value) {
        [("safety_identifier", Json::string(value))]
      },
      ..if provider_options.top_logprobs is Some(value) {
        [("top_logprobs", Json::number(value.to_double()))]
      },
      ..if provider_options.truncation is Some(value) {
        [("truncation", Json::string(value))]
      },
      ..if openai_context_management(provider_options.context_management)
        is Some(value) {
        [("context_management", value)]
      },
      ..if reasoning.length() > 0 {
        [("reasoning", Json::object(reasoning))]
      },
    ],
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    if resolve_openai_responses_tool_choice(
        provider_options.allowed_tools,
        options.tool_choice,
        options.tools,
        tool_name_mapping,
      )
      is Some(choice) {
      fields["tool_choice"] = choice
    }
  }
  { body: Json::object(fields), warnings, tool_name_mapping }
}

///|
/// Encode an official OpenAI Responses API request.
pub fn encode_openai_responses_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name? : String = "openai.responses",
  stream? : Bool = true,
) -> Json raise {
  prepare_openai_responses_request(model_id, options, provider_name, stream).body
}

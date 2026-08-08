///|
fn openai_responses_v4_tool_capabilities(
  tools : Array[@provider.LanguageModelV4Tool],
) -> OpenAIResponsesToolCapabilities {
  let custom_tool_names : Map[String, Bool] = Map([])
  let mut has_local_shell = false
  let mut has_shell = false
  let mut has_apply_patch = false
  let mut has_computer = false
  for tool in tools {
    match tool {
      @provider.V4ProviderTool(value) =>
        match value.id {
          "openai.local_shell" => has_local_shell = true
          "openai.shell" => has_shell = true
          "openai.apply_patch" => has_apply_patch = true
          "openai.computer" => has_computer = true
          "openai.custom" => custom_tool_names[value.name] = true
          _ => ()
        }
      _ => ()
    }
  }
  {
    has_local_shell,
    has_shell,
    has_apply_patch,
    has_computer,
    custom_tool_names,
  }
}

///|
fn openai_responses_v4_shell_provider_executed(
  tools : Array[@provider.LanguageModelV4Tool],
) -> Bool {
  for tool in tools {
    match tool {
      @provider.V4ProviderTool(value) if value.id == "openai.shell" =>
        match value.args {
          { "environment": { "type": String(kind), .. }, .. } if kind ==
            "containerAuto" ||
            kind == "containerReference" => return true
          _ => ()
        }
      _ => ()
    }
  }
  false
}

///|
fn openai_responses_approval_tool_call_ids(
  prompt : @provider.LanguageModelV4Prompt,
  provider_name : String,
) -> Map[String, String] {
  let mapping : Map[String, String] = Map([])
  for message in prompt.messages {
    match message {
      @provider.V4AssistantMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolCall(call) =>
              match
                openai_responses_string_option(
                  call.provider_options,
                  "approvalRequestId",
                  "approval_request_id",
                  provider_name,
                ) {
                Some(approval_id) => mapping[approval_id] = call.tool_call_id
                None => ()
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  mapping
}

///|
fn openai_responses_v4_inline_data(
  data : @provider.LanguageModelV4FileData,
) -> String raise {
  @provider_utils.convert_to_base64(data)
}

///|
fn openai_responses_v4_user_part(
  part : @provider.LanguageModelV4PromptPart,
  pass_through_unsupported_files : Bool,
  index : Int,
  provider_name : String,
) -> Json raise {
  let provider_options = openai_v4_prompt_part_options(part)
  let content : Json = match part {
    @provider.V4PromptText(text~, ..) => openai_input_text(text)
    @provider.V4PromptFile(data~, media_type~, filename~, ..) =>
      match data {
        @provider.V4FileReference(reference) => {
          let file_id = @provider_utils.resolve_provider_reference(
            reference,
            openai_responses_provider_metadata_key(provider_name),
          )
          if @provider_utils.get_top_level_media_type(media_type) == "image" {
            let fields : Map[String, Json] = Map([
              ("type", Json::string("input_image")),
              ("file_id", Json::string(file_id)),
            ])
            if openai_responses_prompt_option(
                provider_options, provider_name, "imageDetail",
              )
              is Some(String(detail)) {
              fields["detail"] = Json::string(detail)
            }
            Json::object(fields)
          } else {
            { "type": "input_file", "file_id": file_id }
          }
        }
        @provider.V4FileText(_) =>
          raise @provider.UnsupportedFunctionalityError(
            functionality="text file parts",
          )
        @provider.V4FileUrl(url) =>
          if @provider_utils.get_top_level_media_type(media_type) == "image" {
            Json::object(
              openai_responses_image_fields(
                url, provider_options, provider_name,
              ),
            )
          } else {
            ({ "type": "input_file", "file_url": url } : Json)
          }
        _ => {
          let encoded = openai_responses_v4_inline_data(data)
          let top_level = @provider_utils.get_top_level_media_type(media_type)
          let full_media_type = @provider_utils.resolve_full_media_type(
            media_type, encoded,
          )
          if top_level == "image" {
            Json::object(
              openai_responses_image_fields(
                openai_data_uri(full_media_type, encoded),
                provider_options,
                provider_name,
              ),
            )
          } else {
            guard full_media_type == "application/pdf" ||
              pass_through_unsupported_files else {
              raise @provider.UnsupportedFunctionalityError(
                functionality="file part media type \{full_media_type}",
              )
            }
            {
              "type": "input_file",
              "filename": filename.unwrap_or(
                if full_media_type == "application/pdf" {
                  "part-\{index}.pdf"
                } else {
                  "part-\{index}"
                },
              ),
              "file_data": openai_data_uri(full_media_type, encoded),
            }
          }
        }
      }
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="non-text/file parts in an OpenAI Responses user message",
      )
  }
  with_openai_responses_prompt_options(content, provider_options, provider_name)
}

///|
fn openai_responses_v4_computer_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  item_id : String,
) -> Json raise {
  let actions = match call.input {
    { "actions": Array(values), .. } => values
    _ => fail("OpenAI computer tool input requires an actions array")
  }
  let mapped_actions : Array[Json] = []
  for action in actions {
    mapped_actions.push(openai_responses_computer_action_wire(action))
  }
  let pending_values = match call.input {
    { "pendingSafetyChecks": Array(values), .. } => values
    _ => fail("OpenAI computer tool input requires pendingSafetyChecks")
  }
  let pending_safety_checks : Array[Json] = []
  for value in pending_values {
    pending_safety_checks.push(
      decode_openai_computer_safety_check(value).to_json(),
    )
  }
  let status = @provider_utils.json_string_field(call.input, "status").unwrap_or_else(() => {
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
    "call_id": call.tool_call_id,
    "id": item_id,
    "status": status,
    "actions": Json::array(mapped_actions),
    "pending_safety_checks": Json::array(pending_safety_checks),
  }
}

///|
fn openai_responses_v4_tool_search_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  item_id : String,
) -> Json raise {
  guard call.input is Object(input) else {
    fail("OpenAI tool search input must be a JSON object")
  }
  let call_id = match input.get("call_id") {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) => fail("OpenAI tool search call_id must be a string or null")
  }
  {
    "type": "tool_search_call",
    "id": item_id,
    "execution": if call_id is Some(_) {
      "client"
    } else {
      "server"
    },
    "call_id": match call_id {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "status": "completed",
    "arguments": input.get("arguments").unwrap_or(Json::null()),
  }
}

///|
fn openai_responses_v4_program_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  item_id : String,
) -> Json raise {
  guard call.input is Object(input) else {
    fail("OpenAI programmatic tool input must be a JSON object")
  }
  guard input.get("code") is Some(String(code)) else {
    fail("OpenAI programmatic tool input requires code")
  }
  guard input.get("fingerprint") is Some(String(fingerprint)) else {
    fail("OpenAI programmatic tool input requires fingerprint")
  }
  {
    "type": "program",
    "id": item_id,
    "call_id": call.tool_call_id,
    "code": code,
    "fingerprint": fingerprint,
  }
}

///|
fn openai_responses_v4_local_shell_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  item_id : String,
) -> Json raise {
  guard call.input is { "action": Object(action), .. } else {
    fail("OpenAI local shell input requires an action object")
  }
  guard action.get("command") is Some(Array(commands)) else {
    fail("OpenAI local shell action requires a command array")
  }
  for command in commands {
    guard command is String(_) else {
      fail("OpenAI local shell command entries must be strings")
    }
  }
  let mapped : Map[String, Json] = Map([
    ("type", Json::string("exec")),
    ("command", Json::array(commands)),
  ])
  match openai_tool_field(action, "timeoutMs", "timeout_ms") {
    Some(Number(value, ..)) => mapped["timeout_ms"] = Json::number(value)
    Some(_) => fail("OpenAI local shell timeoutMs must be a number")
    None => ()
  }
  match openai_tool_field(action, "user", "user") {
    Some(String(value)) => mapped["user"] = Json::string(value)
    Some(_) => fail("OpenAI local shell user must be a string")
    None => ()
  }
  match openai_tool_field(action, "workingDirectory", "working_directory") {
    Some(String(value)) => mapped["working_directory"] = Json::string(value)
    Some(_) => fail("OpenAI local shell workingDirectory must be a string")
    None => ()
  }
  match action.get("env") {
    Some(Object(values)) => {
      for entry in values.iter2() {
        guard entry.1 is String(_) else {
          fail("OpenAI local shell environment values must be strings")
        }
      }
      mapped["env"] = Json::object(values)
    }
    Some(_) => fail("OpenAI local shell env must be an object of strings")
    None => ()
  }
  {
    "type": "local_shell_call",
    "call_id": call.tool_call_id,
    "id": item_id,
    "action": Json::object(mapped),
  }
}

///|
fn openai_responses_v4_shell_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  item_id : String,
) -> Json raise {
  guard call.input is { "action": Object(action), .. } else {
    fail("OpenAI shell input requires an action object")
  }
  guard action.get("commands") is Some(Array(commands)) else {
    fail("OpenAI shell action requires a commands array")
  }
  for command in commands {
    guard command is String(_) else {
      fail("OpenAI shell command entries must be strings")
    }
  }
  let mapped : Map[String, Json] = Map([("commands", Json::array(commands))])
  match openai_tool_field(action, "timeoutMs", "timeout_ms") {
    Some(Number(value, ..)) => mapped["timeout_ms"] = Json::number(value)
    Some(_) => fail("OpenAI shell timeoutMs must be a number")
    None => ()
  }
  match openai_tool_field(action, "maxOutputLength", "max_output_length") {
    Some(Number(value, ..)) => mapped["max_output_length"] = Json::number(value)
    Some(_) => fail("OpenAI shell maxOutputLength must be a number")
    None => ()
  }
  {
    "type": "shell_call",
    "call_id": call.tool_call_id,
    "id": item_id,
    "status": "completed",
    "action": Json::object(mapped),
  }
}

///|
fn openai_responses_v4_apply_patch_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  item_id : String,
) -> Json raise {
  guard call.input is Object(input) else {
    fail("OpenAI apply patch input must be a JSON object")
  }
  guard openai_tool_field(input, "callId", "call_id") is Some(String(call_id)) else {
    fail("OpenAI apply patch input requires callId")
  }
  guard input.get("operation") is Some(Object(_) as operation) else {
    fail("OpenAI apply patch input requires an operation object")
  }
  {
    "type": "apply_patch_call",
    "call_id": call_id,
    "id": item_id,
    "status": "completed",
    "operation": operation,
  }
}

///|
fn openai_responses_v4_custom_tool_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  name : String,
  item_id : String?,
) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("custom_tool_call")),
        ("call_id", Json::string(call.tool_call_id)),
        ("name", Json::string(name)),
        (
          "input",
          Json::string(
            match call.input {
              String(value) => value
              value => value.stringify()
            },
          ),
        ),
        ..if item_id is Some(value) {
          [("id", Json::string(value))]
        },
      ],
    ),
  )
}

///|
fn openai_responses_v4_function_call_wire(
  call : @provider.LanguageModelV4ToolCallPart,
  resolved_tool_name : String,
  provider_options : Map[String, Json],
  provider_name : String,
) -> Json {
  let provider_key_options : Map[String, Json] = match
    provider_options.get(openai_responses_provider_metadata_key(provider_name)) {
    Some(Object(values)) => values
    _ => Map([])
  }
  Json::object(
    Map(
      [
        ("type", Json::string("function_call")),
        ("call_id", Json::string(call.tool_call_id)),
        ("name", Json::string(resolved_tool_name)),
        ("arguments", Json::string(call.input.stringify())),
        ..if provider_key_options.get("namespace")
          is Some(String(tool_namespace)) {
          [("namespace", Json::string(tool_namespace))]
        },
        ..if provider_key_options.get("caller") is Some(caller) &&
          openai_responses_tool_caller_wire(caller) is Some(mapped) {
          [("caller", mapped)]
        },
      ],
    ),
  )
}

///|
fn openai_responses_v4_tool_result_content_part(
  part : @provider.LanguageModelV4ToolResultContentPart,
  pass_through_unsupported_files : Bool,
  index : Int,
  provider_name : String,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match part {
    @provider.V4ToolResultTextContent(text~, provider_options~) =>
      Some(
        openai_responses_v4_user_part(
          @provider.V4PromptText(text~, provider_options~),
          pass_through_unsupported_files,
          index,
          provider_name,
        ),
      )
    @provider.V4ToolResultFileContent(
      data~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      match data {
        @provider.V4FileReference(_) | @provider.V4FileText(_) => {
          let data_type = if data is @provider.V4FileReference(_) {
            "reference"
          } else {
            "text"
          }
          warnings.push(
            @provider.Warning::Other(
              message="unsupported tool content part type: file with data type: \{data_type}",
            ),
          )
          None
        }
        _ =>
          Some(
            openai_responses_v4_user_part(
              @provider.V4PromptFile(
                data~,
                media_type~,
                filename~,
                provider_options~,
              ),
              pass_through_unsupported_files,
              index,
              provider_name,
            ),
          )
      }
    @provider.V4ToolResultCustomContent(..) => {
      warnings.push(
        @provider.Warning::Other(
          message="unsupported tool content part type: custom",
        ),
      )
      None
    }
  }
}

///|
fn openai_responses_v4_tool_result_output(
  output : @provider.LanguageModelV4ToolResultOutput,
  pass_through_unsupported_files : Bool,
  provider_name : String,
  warnings : Array[@provider.Warning],
) -> Json raise {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..)
    | @provider.V4ToolResultErrorText(value~, ..) => Json::string(value)
    @provider.V4ToolResultJsonOutput(value~, ..)
    | @provider.V4ToolResultErrorJson(value~, ..) =>
      Json::string(value.stringify())
    @provider.V4ToolResultExecutionDenied(reason~, ..) =>
      Json::string(reason.unwrap_or("Tool call execution denied."))
    @provider.V4ToolResultContentOutput(value~, ..) => {
      let converted : Array[Json] = []
      for index, part in value {
        match
          openai_responses_v4_tool_result_content_part(
            part, pass_through_unsupported_files, index, provider_name, warnings,
          ) {
          Some(item) => converted.push(item)
          None => ()
        }
      }
      Json::array(converted)
    }
  }
}

///|
fn openai_responses_v4_json_result(
  result : @provider.LanguageModelV4ToolResultPart,
  tool_name : String,
) -> Json raise {
  match result.output {
    @provider.V4ToolResultJsonOutput(value~, ..) => value
    _ => fail("OpenAI \{tool_name} tool result must be JSON")
  }
}

///|
fn openai_responses_v4_tool_search_output_wire(
  result : @provider.LanguageModelV4ToolResultPart,
  item_id : String?,
  execution : String,
) -> Json raise {
  let output = openai_responses_v4_json_result(result, "tool search")
  guard output is { "tools": Array(tools), .. } else {
    fail("OpenAI tool search result requires a tools array")
  }
  Json::object(
    Map(
      [
        ("type", Json::string("tool_search_output")),
        ("execution", Json::string(execution)),
        (
          "call_id",
          if execution == "client" {
            Json::string(result.tool_call_id)
          } else {
            Json::null()
          },
        ),
        ("status", Json::string("completed")),
        ("tools", Json::array(tools)),
        ..if item_id is Some(value) {
          [("id", Json::string(value))]
        },
      ],
    ),
  )
}

///|
fn openai_responses_v4_program_output_wire(
  result : @provider.LanguageModelV4ToolResultPart,
  item_id : String,
) -> Json raise {
  let output = openai_responses_v4_json_result(result, "programmatic")
  guard output is { "result": String(value), "status": String(status), .. } else {
    fail("OpenAI programmatic tool result requires result and status")
  }
  guard status == "completed" || status == "incomplete" else {
    fail("OpenAI programmatic tool result status is invalid")
  }
  {
    "type": "program_output",
    "id": item_id,
    "call_id": result.tool_call_id,
    "result": value,
    "status": status,
  }
}

///|
fn openai_responses_v4_local_shell_output_wire(
  result : @provider.LanguageModelV4ToolResultPart,
) -> Json raise {
  let output = openai_responses_v4_json_result(result, "local shell")
  guard output is { "output": String(value), .. } else {
    fail("OpenAI local shell result requires output text")
  }
  {
    "type": "local_shell_call_output",
    "call_id": result.tool_call_id,
    "output": value,
  }
}

///|
fn openai_responses_v4_shell_output_wire(
  result : @provider.LanguageModelV4ToolResultPart,
) -> Json raise {
  let output = openai_responses_v4_json_result(result, "shell")
  guard output is { "output": Array(items), .. } else {
    fail("OpenAI shell result requires an output array")
  }
  let mapped : Array[Json] = []
  for item in items {
    guard item
      is {
        "stdout": String(stdout),
        "stderr": String(stderr),
        "outcome": Object(outcome),
        ..
      } else {
      fail("OpenAI shell result entries are invalid")
    }
    let exit_code = fn() -> Json raise {
      match outcome.get("exitCode") {
        Some(Number(value, ..)) => Json::number(value)
        Some(_) => fail("OpenAI shell exitCode must be a number")
        None =>
          match outcome.get("exit_code") {
            Some(Number(value, ..)) => Json::number(value)
            Some(_) => fail("OpenAI shell exit_code must be a number")
            None => fail("OpenAI shell exit outcome requires exitCode")
          }
      }
    }
    let outcome_wire : Json = match outcome.get("type") {
      Some(String("timeout")) => { "type": "timeout" }
      Some(String("exit")) => { "type": "exit", "exit_code": exit_code() }
      _ => fail("OpenAI shell result outcome type is invalid")
    }
    mapped.push({ "stdout": stdout, "stderr": stderr, "outcome": outcome_wire })
  }
  {
    "type": "shell_call_output",
    "call_id": result.tool_call_id,
    "output": Json::array(mapped),
  }
}

///|
fn openai_responses_v4_apply_patch_output_wire(
  result : @provider.LanguageModelV4ToolResultPart,
) -> Json raise {
  let output = openai_responses_v4_json_result(result, "apply patch")
  guard output is { "status": String(status), .. } else {
    fail("OpenAI apply patch result requires status")
  }
  guard status == "completed" || status == "failed" else {
    fail("OpenAI apply patch result status is invalid")
  }
  let fields : Map[String, Json] = Map([
    ("type", Json::string("apply_patch_call_output")),
    ("call_id", Json::string(result.tool_call_id)),
    ("status", Json::string(status)),
  ])
  match output {
    { "output": String(value), .. } => fields["output"] = Json::string(value)
    _ => ()
  }
  Json::object(fields)
}

///|
fn openai_responses_v4_tool_result_to_wire(
  result : @provider.LanguageModelV4ToolResultPart,
  pass_through_unsupported_files : Bool,
  provider_name : String,
  warnings : Array[@provider.Warning],
) -> Json raise {
  let fields : Map[String, Json] = Map([
    ("type", Json::string("function_call_output")),
    ("call_id", Json::string(result.tool_call_id)),
    (
      "output",
      openai_responses_v4_tool_result_output(
        result.output,
        pass_through_unsupported_files,
        provider_name,
        warnings,
      ),
    ),
  ])
  match
    openai_responses_prompt_option(
      result.provider_options,
      provider_name,
      "caller",
    ) {
    Some(caller) if openai_responses_tool_caller_wire(caller) is Some(mapped) =>
      fields["caller"] = mapped
    _ => ()
  }
  Json::object(fields)
}

///|
fn openai_responses_v4_custom_tool_output_wire(
  result : @provider.LanguageModelV4ToolResultPart,
  pass_through_unsupported_files : Bool,
  provider_name : String,
  warnings : Array[@provider.Warning],
) -> Json raise {
  {
    "type": "custom_tool_call_output",
    "call_id": result.tool_call_id,
    "output": openai_responses_v4_tool_result_output(
      result.output,
      pass_through_unsupported_files,
      provider_name,
      warnings,
    ),
  }
}

///|
fn openai_responses_v4_tool_approval_response_to_wire(
  response : @provider.LanguageModelV4ToolApprovalResponsePart,
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
fn append_openai_responses_v4_assistant_tool_result(
  result : @provider.LanguageModelV4ToolResultPart,
  capabilities : OpenAIResponsesToolCapabilities,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  pass_through_unsupported_files : Bool,
  provider_name : String,
  store : Bool,
  warnings : Array[@provider.Warning],
  input : Array[Json],
) -> Unit raise {
  if result.output is @provider.V4ToolResultExecutionDenied(..) {
    return
  }
  let resolved_name = tool_name_mapping.to_provider_tool_name(result.tool_name)
  let item_id = openai_responses_string_option(
    result.provider_options,
    "itemId",
    "item_id",
    provider_name,
  ).unwrap_or(result.tool_call_id)
  if resolved_name == "tool_search" {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      input.push(
        openai_responses_v4_tool_search_output_wire(
          result,
          Some(item_id),
          "server",
        ),
      )
    }
  } else if resolved_name == "programmatic_tool_calling" {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      input.push(openai_responses_v4_program_output_wire(result, item_id))
    }
  } else if capabilities.has_local_shell && resolved_name == "local_shell" {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      input.push(openai_responses_v4_local_shell_output_wire(result))
    }
  } else if capabilities.has_shell && resolved_name == "shell" {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      input.push(openai_responses_v4_shell_output_wire(result))
    }
  } else if capabilities.has_apply_patch && resolved_name == "apply_patch" {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      input.push(openai_responses_v4_apply_patch_output_wire(result))
    }
  } else if capabilities.has_computer && resolved_name == "computer" {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      let output = openai_responses_v4_json_result(result, "computer")
      input.push(
        openai_responses_computer_output_wire(
          result.tool_call_id,
          output.stringify(),
        ),
      )
    }
  } else if capabilities.is_custom_tool(resolved_name) {
    input.push(
      openai_responses_v4_custom_tool_output_wire(
        result, pass_through_unsupported_files, provider_name, warnings,
      ),
    )
  } else if openai_responses_bool_option(
      result.provider_options,
      "providerExecuted",
      "provider_executed",
      provider_name,
    ) {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      warnings.push(
        @provider.Warning::Other(
          message="Results for OpenAI provider-executed tools are not sent when store is false.",
        ),
      )
    }
  } else {
    input.push(
      openai_responses_v4_tool_result_to_wire(
        result, pass_through_unsupported_files, provider_name, warnings,
      ),
    )
  }
}

///|
fn openai_responses_v4_tool_result_output_options(
  output : @provider.LanguageModelV4ToolResultOutput,
) -> Map[String, Json] {
  match output {
    @provider.V4ToolResultTextOutput(provider_options~, ..)
    | @provider.V4ToolResultJsonOutput(provider_options~, ..)
    | @provider.V4ToolResultExecutionDenied(provider_options~, ..)
    | @provider.V4ToolResultErrorText(provider_options~, ..)
    | @provider.V4ToolResultErrorJson(provider_options~, ..)
    | @provider.V4ToolResultContentOutput(provider_options~, ..) =>
      provider_options
  }
}

///|
fn append_openai_responses_v4_assistant_tool_call(
  call : @provider.LanguageModelV4ToolCallPart,
  capabilities : OpenAIResponsesToolCapabilities,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  store : Bool,
  has_conversation : Bool,
  has_previous_response_id : Bool,
  provider_name : String,
  provider_executed_tool_calls : Map[String, Bool],
  input : Array[Json],
) -> Unit raise {
  let resolved_tool_name = tool_name_mapping.to_provider_tool_name(
    call.tool_name,
  )
  let item_id = openai_responses_string_option(
    call.provider_options,
    "itemId",
    "item_id",
    provider_name,
  )
  if call.provider_executed {
    provider_executed_tool_calls[call.tool_call_id] = true
  }
  if has_conversation && item_id is Some(_) {
    return
  }
  if resolved_tool_name == "tool_search" {
    if store && item_id is Some(id) {
      input.push({ "type": "item_reference", "id": id })
    } else {
      input.push(
        openai_responses_v4_tool_search_call_wire(
          call,
          item_id.unwrap_or(call.tool_call_id),
        ),
      )
    }
    return
  }
  if resolved_tool_name == "programmatic_tool_calling" {
    if store && item_id is Some(id) {
      input.push({ "type": "item_reference", "id": id })
    } else {
      input.push(
        openai_responses_v4_program_call_wire(
          call,
          item_id.unwrap_or(call.tool_call_id),
        ),
      )
    }
    return
  }
  if call.provider_executed {
    if store && item_id is Some(id) {
      input.push({ "type": "item_reference", "id": id })
    }
    return
  }
  if capabilities.is_stored_provider_tool(resolved_tool_name) &&
    store &&
    item_id is Some(id) {
    input.push({ "type": "item_reference", "id": id })
    return
  }
  if has_previous_response_id && store && item_id is Some(_) {
    return
  }
  let resolved_item_id = item_id.unwrap_or(call.tool_call_id)
  if capabilities.has_local_shell && resolved_tool_name == "local_shell" {
    input.push(
      openai_responses_v4_local_shell_call_wire(call, resolved_item_id),
    )
  } else if capabilities.has_shell && resolved_tool_name == "shell" {
    input.push(openai_responses_v4_shell_call_wire(call, resolved_item_id))
  } else if capabilities.has_apply_patch && resolved_tool_name == "apply_patch" {
    input.push(
      openai_responses_v4_apply_patch_call_wire(call, resolved_item_id),
    )
  } else if capabilities.has_computer && resolved_tool_name == "computer" {
    input.push(openai_responses_v4_computer_call_wire(call, resolved_item_id))
  } else if capabilities.is_custom_tool(resolved_tool_name) {
    input.push(
      openai_responses_v4_custom_tool_call_wire(
        call, resolved_tool_name, item_id,
      ),
    )
  } else {
    input.push(
      openai_responses_v4_function_call_wire(
        call,
        resolved_tool_name,
        call.provider_options,
        provider_name,
      ),
    )
  }
}

///|
fn append_openai_responses_v4_tool_result(
  result : @provider.LanguageModelV4ToolResultPart,
  capabilities : OpenAIResponsesToolCapabilities,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  pass_through_unsupported_files : Bool,
  provider_name : String,
  store : Bool,
  provider_executed_tool_calls : Map[String, Bool],
  warnings : Array[@provider.Warning],
  input : Array[Json],
) -> Unit raise {
  let output_options = openai_responses_v4_tool_result_output_options(
    result.output,
  )
  let approval_id = match
    openai_responses_string_option(
      output_options, "approvalId", "approval_id", provider_name,
    ) {
    Some(value) => Some(value)
    None =>
      openai_responses_string_option(
        result.provider_options,
        "approvalId",
        "approval_id",
        provider_name,
      )
  }
  if result.output is @provider.V4ToolResultExecutionDenied(..) &&
    approval_id is Some(_) {
    return
  }
  let resolved_name = tool_name_mapping.to_provider_tool_name(result.tool_name)
  let provider_executed = provider_executed_tool_calls.get(result.tool_call_id)
    is Some(_) ||
    openai_responses_bool_option(
      result.provider_options,
      "providerExecuted",
      "provider_executed",
      provider_name,
    )
  let item_id = openai_responses_string_option(
    result.provider_options,
    "itemId",
    "item_id",
    provider_name,
  ).unwrap_or(result.tool_call_id)
  if resolved_name == "tool_search" {
    input.push(
      openai_responses_v4_tool_search_output_wire(result, None, "client"),
    )
  } else if resolved_name == "programmatic_tool_calling" {
    input.push(openai_responses_v4_program_output_wire(result, item_id))
  } else if capabilities.has_local_shell && resolved_name == "local_shell" {
    input.push(openai_responses_v4_local_shell_output_wire(result))
  } else if capabilities.has_shell && resolved_name == "shell" {
    input.push(openai_responses_v4_shell_output_wire(result))
  } else if capabilities.has_apply_patch && resolved_name == "apply_patch" {
    input.push(openai_responses_v4_apply_patch_output_wire(result))
  } else if capabilities.has_computer && resolved_name == "computer" {
    let output = openai_responses_v4_json_result(result, "computer")
    input.push(
      openai_responses_computer_output_wire(
        result.tool_call_id,
        output.stringify(),
      ),
    )
  } else if capabilities.is_custom_tool(resolved_name) {
    input.push(
      openai_responses_v4_custom_tool_output_wire(
        result, pass_through_unsupported_files, provider_name, warnings,
      ),
    )
  } else if provider_executed {
    if store {
      input.push({ "type": "item_reference", "id": item_id })
    } else {
      warnings.push(
        @provider.Warning::Other(
          message="Results for OpenAI provider-executed tools are not sent when store is false.",
        ),
      )
    }
  } else {
    input.push(
      openai_responses_v4_tool_result_to_wire(
        result, pass_through_unsupported_files, provider_name, warnings,
      ),
    )
  }
}

///|
/// Convert a normalized provider V4 prompt directly to Responses input.
///
/// This is the MoonBit equivalent of AI SDK's
/// `convertToOpenAIResponsesInput`: provider prompt parts stay structured until
/// this wire-format boundary, including raw bytes and structured tool input.
fn convert_v4_prompt_to_openai_responses(
  prompt : @provider.LanguageModelV4Prompt,
  system_message_mode : String,
  pass_through_unsupported_files : Bool,
  provider_name : String,
  store : Bool,
  has_conversation : Bool,
  has_previous_response_id : Bool,
  warnings : Array[@provider.Warning],
  tool_name_mapping : @provider_utils.ToolNameMapping,
  capabilities : OpenAIResponsesToolCapabilities,
) -> Array[Json] raise {
  let input : Array[Json] = []
  let reasoning_item_indices : Map[String, Int] = Map([])
  let reasoning_references : Map[String, Bool] = Map([])
  let reasoning_items_with_encrypted_content : Map[String, Bool] = Map([])
  let provider_executed_tool_calls : Map[String, Bool] = Map([])
  let processed_approval_ids : Map[String, Bool] = Map([])
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, provider_options~) =>
        if system_message_mode == "remove" {
          warnings.push(
            @provider.Warning::Other(
              message="system messages are removed for this model",
            ),
          )
        } else {
          let wire_content = match
            openai_responses_prompt_option(
              provider_options, provider_name, "promptCacheBreakpoint",
            ) {
            Some(_) =>
              Json::array([
                with_openai_responses_prompt_options(
                  openai_input_text(content),
                  provider_options,
                  provider_name,
                ),
              ])
            None => Json::string(content)
          }
          input.push(openai_message_item(system_message_mode, wire_content))
        }
      @provider.V4UserMessage(content~, ..) => {
        let parts : Array[Json] = []
        for index, part in content {
          parts.push(
            openai_responses_v4_user_part(
              part, pass_through_unsupported_files, index, provider_name,
            ),
          )
        }
        input.push(openai_message_item("user", Json::array(parts)))
      }
      @provider.V4AssistantMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptText(text~, provider_options~) => {
              let item_id = openai_responses_string_option(
                provider_options, "itemId", "item_id", provider_name,
              )
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
                          openai_output_text(text),
                          provider_options,
                          provider_name,
                        ),
                      ]),
                    ),
                    ..if item_id is Some(id) {
                      [("id", Json::string(id))]
                    },
                    ..if openai_responses_prompt_option(
                        provider_options, provider_name, "phase",
                      )
                      is Some(String(phase)) {
                      [("phase", Json::string(phase))]
                    },
                  ],
                )
                input.push(Json::object(fields))
              }
            }
            @provider.V4PromptReasoning(text~, provider_options~) =>
              append_openai_reasoning_part(
                text, provider_options, input, warnings, store, has_conversation,
                has_previous_response_id, reasoning_item_indices, reasoning_references,
                reasoning_items_with_encrypted_content, provider_name,
              )
            @provider.V4PromptReasoningFile(..) =>
              warnings.push(
                @provider.Warning::Other(
                  message="OpenAI Responses does not support reasoning file parts in prompt history.",
                ),
              )
            @provider.V4PromptCustom(kind~, provider_options~) =>
              if kind == "openai.compaction" {
                append_openai_compaction_input(
                  provider_options, input, store, has_conversation, provider_name,
                )
              }
            @provider.V4PromptToolCall(call) =>
              append_openai_responses_v4_assistant_tool_call(
                call, capabilities, tool_name_mapping, store, has_conversation, has_previous_response_id,
                provider_name, provider_executed_tool_calls, input,
              )
            @provider.V4PromptToolResult(result) =>
              append_openai_responses_v4_assistant_tool_result(
                result, capabilities, tool_name_mapping, pass_through_unsupported_files,
                provider_name, store, warnings, input,
              )
            @provider.V4PromptToolApprovalResponse(response) =>
              openai_responses_v4_tool_approval_response_to_wire(
                response, store, input, processed_approval_ids,
              )
            @provider.V4PromptFile(..) =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="file parts in an OpenAI Responses assistant message",
              )
          }
        }
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result) =>
              append_openai_responses_v4_tool_result(
                result, capabilities, tool_name_mapping, pass_through_unsupported_files,
                provider_name, store, provider_executed_tool_calls, warnings, input,
              )
            @provider.V4PromptToolApprovalResponse(response) =>
              openai_responses_v4_tool_approval_response_to_wire(
                response, store, input, processed_approval_ids,
              )
            _ =>
              warnings.push(
                @provider.Warning::Other(
                  message="OpenAI Responses ignored an unsupported part in a tool message.",
                ),
              )
          }
        }
    }
  }
  finalize_openai_reasoning_input(
    input, warnings, reasoning_items_with_encrypted_content,
  )
}

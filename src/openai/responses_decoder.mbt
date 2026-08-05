///|
fn openai_responses_response_error(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn openai_responses_usage(json : Json) -> @provider.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "input_tokens")
  let output_tokens = @provider_utils.json_int_field(json, "output_tokens")
  let total_tokens = @provider_utils.json_int_field(
    json,
    "total_tokens",
    default=input_tokens + output_tokens,
  )
  let cached_input_tokens = match json {
    { "input_tokens_details": { "cached_tokens": Number(value, ..), .. }, .. } =>
      value.to_int()
    _ => 0
  }
  let reasoning_tokens = match json {
    {
      "output_tokens_details": { "reasoning_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  let cache_write_input_tokens = match json {
    {
      "input_tokens_details": { "cache_write_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  {
    input_tokens,
    output_tokens,
    total_tokens,
    reasoning_tokens,
    cached_input_tokens,
    cache_write_input_tokens,
  }
}

///|
fn openai_responses_item_metadata(
  provider_name : String,
  item_id : String,
  extra_fields? : Map[String, Json] = Map([]),
) -> Map[String, Json] {
  if item_id == "" && extra_fields.length() == 0 {
    return Map([])
  }
  let key = openai_provider_metadata_key(provider_name)
  let fields : Map[String, Json] = Map([])
  if item_id != "" {
    fields["itemId"] = Json::string(item_id)
  }
  for entry in extra_fields.iter2() {
    fields[entry.0] = entry.1
  }
  Map([(key, Json::object(fields))])
}

///|
fn openai_responses_text_item_metadata(
  provider_name : String,
  item_id : String,
  item : Json,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  if @provider_utils.json_string_field(item, "phase") is Some(value) {
    fields["phase"] = Json::string(value)
  }
  openai_responses_item_metadata(provider_name, item_id, extra_fields=fields)
}

///|
fn openai_responses_tool_item_metadata(
  provider_name : String,
  item_id : String,
  item : Json,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  if @provider_utils.json_string_field(item, "namespace") is Some(value) {
    fields["namespace"] = Json::string(value)
  }
  openai_responses_item_metadata(provider_name, item_id, extra_fields=fields)
}

///|
fn openai_responses_string_or_json(value : Json) -> String {
  match value {
    String(text) => text
    other => other.stringify()
  }
}

///|
fn openai_responses_computer_call_input(item : Json) -> Json raise {
  let action_values = match item {
    { "actions": Array(values), .. } => values
    { "action": Null, .. } => []
    { "action": action, .. } => [action]
    _ => []
  }
  let actions : Array[Json] = []
  for value in action_values {
    actions.push(decode_openai_computer_action(value).to_json())
  }
  let safety_values = match item {
    { "pending_safety_checks": Array(values), .. } => values
    _ => []
  }
  let safety_checks : Array[Json] = []
  for value in safety_values {
    safety_checks.push(decode_openai_computer_safety_check(value).to_json())
  }
  let status = @provider_utils.json_string_field(item, "status").unwrap_or_else(() => {
      fail("OpenAI computer call requires a status")
    },
  )
  guard status == "in_progress" ||
    status == "completed" ||
    status == "incomplete" else {
    fail("Unsupported OpenAI computer call status '\{status}'")
  }
  {
    "actions": Json::array(actions),
    "pendingSafetyChecks": Json::array(safety_checks),
    "status": status,
  }
}

///|
fn openai_responses_tool_call(
  id : String,
  name : String,
  arguments : String,
  provider_name : String,
  item_id : String,
  provider_executed? : Bool = false,
  dynamic? : Bool = false,
  provider_metadata? : Map[String, Json] = openai_responses_item_metadata(
    provider_name, item_id,
  ),
) -> @provider.ToolCall {
  @provider.ToolCall::new(
    id~,
    name~,
    arguments~,
    provider_executed~,
    dynamic~,
    provider_metadata~,
  )
}

///|
fn openai_responses_tool_result(
  tool_call_id : String,
  tool_name : String,
  result : Json,
  provider_name : String,
  item_id : String,
  is_error? : Bool = false,
  preliminary? : Bool = false,
  dynamic? : Bool = false,
) -> @provider.ToolResult {
  @provider.ToolResult::new(
    tool_call_id~,
    tool_name~,
    result~,
    is_error~,
    preliminary~,
    dynamic~,
    provider_metadata=openai_responses_item_metadata(provider_name, item_id),
  )
}

///|
fn openai_responses_source_contents(
  annotations : Array[Json],
  provider_name : String,
  item_id : String,
  index : Int,
  id_generator : @provider_utils.IdGenerator,
) -> Array[@provider.GeneratedContent] {
  let sources : Array[@provider.GeneratedContent] = []
  for annotation_index, annotation in annotations {
    let generated = id_generator()
    let source_id = if generated == "" {
      "source-\{index}-\{annotation_index}"
    } else {
      generated
    }
    match annotation {
      { "type": "url_citation", "url": String(url), "title": title, .. } =>
        match title {
          String(value) =>
            sources.push(
              @provider.GeneratedContent::url_source(
                id=source_id,
                url~,
                title=value,
                provider_metadata=openai_responses_item_metadata(
                  provider_name, item_id,
                ),
              ),
            )
          _ =>
            sources.push(
              @provider.GeneratedContent::url_source(
                id=source_id,
                url~,
                provider_metadata=openai_responses_item_metadata(
                  provider_name, item_id,
                ),
              ),
            )
        }
      {
        "type": "file_citation",
        "file_id": String(file_id),
        "filename": String(filename),
        "index": citation_index,
        ..
      } =>
        sources.push(
          @provider.GeneratedContent::document_source(
            id=source_id,
            media_type="text/plain",
            title=filename,
            filename~,
            provider_metadata=Map([
              (
                openai_provider_metadata_key(provider_name),
                {
                  "type": "file_citation",
                  "fileId": file_id,
                  "index": citation_index,
                  "itemId": item_id,
                },
              ),
            ]),
          ),
        )
      {
        "type": "container_file_citation",
        "file_id": String(file_id),
        "filename": String(filename),
        "container_id": String(container_id),
        ..
      } =>
        sources.push(
          @provider.GeneratedContent::document_source(
            id=source_id,
            media_type="text/plain",
            title=filename,
            filename~,
            provider_metadata=Map([
              (
                openai_provider_metadata_key(provider_name),
                {
                  "type": "container_file_citation",
                  "fileId": file_id,
                  "containerId": container_id,
                },
              ),
            ]),
          ),
        )
      {
        "type": "file_path",
        "file_id": String(file_id),
        "index": citation_index,
        ..
      } =>
        sources.push(
          @provider.GeneratedContent::document_source(
            id=source_id,
            media_type="application/octet-stream",
            title=file_id,
            filename=file_id,
            provider_metadata=Map([
              (
                openai_provider_metadata_key(provider_name),
                {
                  "type": "file_path",
                  "fileId": file_id,
                  "index": citation_index,
                  "itemId": item_id,
                },
              ),
            ]),
          ),
        )
      _ => ()
    }
  }
  sources
}

///|
fn append_openai_mcp_approval(
  content : Array[@provider.GeneratedContent],
  provider_name : String,
  item_id : String,
  approval_id : String,
  name : String,
  arguments : Json,
  id_generator : @provider_utils.IdGenerator,
) -> Unit {
  let generated = id_generator()
  let tool_call_id = if generated == "" { item_id } else { generated }
  let call = openai_responses_tool_call(
    tool_call_id,
    "mcp.\{name}",
    openai_responses_string_or_json(arguments),
    provider_name,
    item_id,
    provider_executed=true,
    dynamic=true,
  )
  content.push(@provider.GeneratedContent::tool_call(call))
  content.push(
    @provider.GeneratedContent::tool_approval_request(
      @provider.ToolApprovalRequest::new(
        approval_id~,
        tool_call_id~,
        provider_metadata=openai_responses_item_metadata(provider_name, item_id),
      ),
    ),
  )
}

///|
fn openai_responses_output_content(
  output : Array[Json],
  provider_name : String,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  id_generator : @provider_utils.IdGenerator,
) -> (Array[@provider.GeneratedContent], Bool) {
  let content : Array[@provider.GeneratedContent] = []
  let mut has_function_call = false
  let hosted_tool_search_call_ids : Array[String] = []
  let mut hosted_tool_search_result_index = 0
  for index, item in output {
    match item {
      { "type": "message", "id": String(item_id), "content": Array(parts), .. } =>
        for part_index, part in parts {
          match part {
            {
              "type": "output_text",
              "text": String(text),
              "annotations": Array(annotations),
              ..
            } => {
              content.push(
                @provider.GeneratedContent::text(
                  text,
                  provider_metadata=openai_responses_text_item_metadata(
                    provider_name, item_id, item,
                  ),
                ),
              )
              for
                source in openai_responses_source_contents(
                  annotations,
                  provider_name,
                  item_id,
                  index + part_index,
                  id_generator,
                ) {
                content.push(source)
              }
            }
            { "type": "output_text", "text": String(text), .. }
            | { "type": "refusal", "refusal": String(text), .. } =>
              content.push(
                @provider.GeneratedContent::text(
                  text,
                  provider_metadata=openai_responses_text_item_metadata(
                    provider_name, item_id, item,
                  ),
                ),
              )
            _ => ()
          }
        }
      { "type": "message", "content": Array(parts), .. } =>
        for part_index, part in parts {
          match part {
            {
              "type": "output_text",
              "text": String(text),
              "annotations": Array(annotations),
              ..
            } => {
              content.push(@provider.GeneratedContent::text(text))
              for
                source in openai_responses_source_contents(
                  annotations,
                  provider_name,
                  "",
                  index + part_index,
                  id_generator,
                ) {
                content.push(source)
              }
            }
            { "type": "output_text", "text": String(text), .. }
            | { "type": "refusal", "refusal": String(text), .. } =>
              content.push(@provider.GeneratedContent::text(text))
            _ => ()
          }
        }
      {
        "type": "reasoning",
        "id": String(item_id),
        "summary": Array(parts),
        "encrypted_content": encrypted_content,
        ..
      } =>
        for part in parts {
          match part {
            { "type": "summary_text", "text": String(text), .. }
            | { "type": "reasoning_text", "text": String(text), .. } =>
              content.push(
                @provider.GeneratedContent::reasoning(
                  text,
                  provider_metadata=Map([
                    (
                      openai_provider_metadata_key(provider_name),
                      {
                        "itemId": item_id,
                        "reasoningEncryptedContent": encrypted_content,
                      },
                    ),
                  ]),
                ),
              )
            _ => ()
          }
        }
      {
        "type": "reasoning",
        "id": String(item_id),
        "summary": Array(parts),
        ..
      } =>
        for part in parts {
          match part {
            { "type": "summary_text", "text": String(text), .. }
            | { "type": "reasoning_text", "text": String(text), .. } =>
              content.push(
                @provider.GeneratedContent::reasoning(
                  text,
                  provider_metadata=openai_responses_item_metadata(
                    provider_name, item_id,
                  ),
                ),
              )
            _ => ()
          }
        }
      {
        "type": "function_call",
        "id": String(item_id),
        "call_id": String(call_id),
        "name": String(name),
        "arguments": String(arguments),
        ..
      } => {
        has_function_call = true
        content.push(
          @provider.GeneratedContent::tool_call(
            openai_responses_tool_call(
              call_id,
              name,
              arguments,
              provider_name,
              item_id,
              provider_metadata=openai_responses_tool_item_metadata(
                provider_name, item_id, item,
              ),
            ),
          ),
        )
      }
      {
        "type": "custom_tool_call",
        "id": String(item_id),
        "call_id": String(call_id),
        "name": String(name),
        "input": input,
        ..
      } => {
        has_function_call = true
        content.push(
          @provider.GeneratedContent::tool_call(
            openai_responses_tool_call(
              call_id,
              name,
              openai_responses_string_or_json(input),
              provider_name,
              item_id,
              provider_metadata=openai_responses_tool_item_metadata(
                provider_name, item_id, item,
              ),
            ),
          ),
        )
      }
      {
        "type": "tool_search_call",
        "id": String(item_id),
        "arguments": arguments,
        ..
      } => {
        let execution = @provider_utils.json_string_field(item, "execution").unwrap_or(
          "server",
        )
        let provider_executed = execution == "server"
        let call_id = @provider_utils.json_string_field(item, "call_id").unwrap_or(
          item_id,
        )
        if provider_executed {
          hosted_tool_search_call_ids.push(call_id)
        }
        let input_fields : Map[String, Json] = Map([
          ("arguments", arguments),
          (
            "call_id",
            match @provider_utils.json_string_field(item, "call_id") {
              Some(value) => Json::string(value)
              None => Json::null()
            },
          ),
        ])
        content.push(
          @provider.GeneratedContent::tool_call(
            openai_responses_tool_call(
              call_id,
              "tool_search",
              Json::object(input_fields).stringify(),
              provider_name,
              item_id,
              provider_executed~,
            ),
          ),
        )
      }
      {
        "type": "tool_search_output",
        "id": String(item_id),
        "tools": tools,
        ..
      } => {
        let call_id = match @provider_utils.json_string_field(item, "call_id") {
          Some(value) => value
          None =>
            if hosted_tool_search_result_index <
              hosted_tool_search_call_ids.length() {
              let value = hosted_tool_search_call_ids[hosted_tool_search_result_index]
              hosted_tool_search_result_index = hosted_tool_search_result_index +
                1
              value
            } else {
              item_id
            }
        }
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              call_id,
              "tool_search",
              { "tools": tools },
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "image_generation_call",
        "id": String(item_id),
        "result": result,
        ..
      } => {
        let call = openai_responses_tool_call(
          item_id,
          "image_generation",
          "{}",
          provider_name,
          item_id,
          provider_executed=true,
        )
        content.push(@provider.GeneratedContent::tool_call(call))
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              item_id,
              "image_generation",
              { "result": result },
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "file_search_call",
        "id": String(item_id),
        "queries": queries,
        "results": results,
        ..
      } => {
        let call = openai_responses_tool_call(
          item_id,
          "file_search",
          "{}",
          provider_name,
          item_id,
          provider_executed=true,
        )
        content.push(@provider.GeneratedContent::tool_call(call))
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              item_id,
              "file_search",
              { "queries": queries, "results": results },
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "code_interpreter_call",
        "id": String(item_id),
        "code": code,
        "container_id": String(container_id),
        "outputs": outputs,
        ..
      } => {
        let call = openai_responses_tool_call(
          item_id,
          "code_interpreter",
          ({ "code": code, "containerId": container_id } : Json).stringify(),
          provider_name,
          item_id,
          provider_executed=true,
        )
        content.push(@provider.GeneratedContent::tool_call(call))
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              item_id,
              "code_interpreter",
              { "outputs": outputs },
              provider_name,
              item_id,
            ),
          ),
        )
      }
      { "type": "web_search_call", "id": String(item_id), "action": action, .. } => {
        let call = openai_responses_tool_call(
          item_id,
          "web_search",
          "{}",
          provider_name,
          item_id,
          provider_executed=true,
        )
        content.push(@provider.GeneratedContent::tool_call(call))
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              item_id, "web_search", action, provider_name, item_id,
            ),
          ),
        )
      }
      {
        "type": "computer_call",
        "id": String(item_id),
        "call_id": String(call_id),
        ..
      } as item => {
        has_function_call = true
        let computer_input = openai_responses_computer_call_input(item) catch {
          _ =>
            {
              "actions": match item {
                { "actions": Array(actions), .. } => Json::array(actions)
                { "action": action, .. } => Json::array([action])
                _ => Json::array([])
              },
            }
        }
        content.push(
          @provider.GeneratedContent::tool_call(
            openai_responses_tool_call(
              call_id,
              "computer",
              computer_input.stringify(),
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "computer_call",
        "id": String(item_id),
        "status": String(status),
        ..
      } => {
        let call = openai_responses_tool_call(
          item_id,
          "computer_use",
          "",
          provider_name,
          item_id,
          provider_executed=true,
        )
        content.push(@provider.GeneratedContent::tool_call(call))
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              item_id,
              "computer_use",
              { "type": "computer_use_tool_result", "status": status },
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "apply_patch_call",
        "id": String(item_id),
        "call_id": String(call_id),
        "operation": operation,
        ..
      } => {
        has_function_call = true
        content.push(
          @provider.GeneratedContent::tool_call(
            openai_responses_tool_call(
              call_id,
              "apply_patch",
              ({ "callId": call_id, "operation": operation } : Json).stringify(),
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "local_shell_call",
        "id": String(item_id),
        "call_id": String(call_id),
        "action": action,
        ..
      } => {
        has_function_call = true
        content.push(
          @provider.GeneratedContent::tool_call(
            openai_responses_tool_call(
              call_id,
              "local_shell",
              ({ "action": action } : Json).stringify(),
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "shell_call",
        "id": String(item_id),
        "call_id": String(call_id),
        "action": action,
        ..
      } => {
        has_function_call = true
        content.push(
          @provider.GeneratedContent::tool_call(
            openai_responses_tool_call(
              call_id,
              "shell",
              ({ "action": action } : Json).stringify(),
              provider_name,
              item_id,
            ),
          ),
        )
      }
      {
        "type": "shell_call_output",
        "id": String(item_id),
        "call_id": String(call_id),
        "output": output,
        ..
      } =>
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              call_id,
              "shell",
              { "output": output },
              provider_name,
              item_id,
            ),
          ),
        )
      {
        "type": "program",
        "id": String(item_id),
        "call_id": String(call_id),
        "code": code,
        "fingerprint": fingerprint,
        ..
      } => {
        let call = openai_responses_tool_call(
          call_id,
          "programmatic_tool_calling",
          ({ "code": code, "fingerprint": fingerprint } : Json).stringify(),
          provider_name,
          item_id,
          provider_executed=true,
        )
        content.push(@provider.GeneratedContent::tool_call(call))
      }
      {
        "type": "program_output",
        "id": String(item_id),
        "call_id": String(call_id),
        "result": result,
        "status": status,
        ..
      } =>
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              call_id,
              "programmatic_tool_calling",
              { "result": result, "status": status },
              provider_name,
              item_id,
            ),
          ),
        )
      {
        "type": "mcp_call",
        "id": String(item_id),
        "name": String(name),
        "server_label": String(server_label),
        "arguments": arguments,
        ..
      } => {
        let tool_name = "mcp.\{name}"
        let call = openai_responses_tool_call(
          item_id,
          tool_name,
          openai_responses_string_or_json(arguments),
          provider_name,
          item_id,
          provider_executed=true,
          dynamic=true,
        )
        content.push(@provider.GeneratedContent::tool_call(call))
        let result_fields : Map[String, Json] = Map([
          ("type", Json::string("call")),
          ("serverLabel", Json::string(server_label)),
          ("name", Json::string(name)),
          ("arguments", arguments),
        ])
        match item {
          Object(item_fields) => {
            if item_fields.get("output") is Some(value) {
              result_fields["output"] = value
            }
            if item_fields.get("error") is Some(value) {
              result_fields["error"] = value
            }
          }
          _ => ()
        }
        content.push(
          @provider.GeneratedContent::tool_result(
            openai_responses_tool_result(
              item_id,
              tool_name,
              Json::object(result_fields),
              provider_name,
              item_id,
              dynamic=true,
            ),
          ),
        )
      }
      {
        "type": "mcp_approval_request",
        "id": String(item_id),
        "approval_request_id": approval_request_id,
        "name": String(name),
        "arguments": arguments,
        ..
      } => {
        let approval_id = openai_responses_string_or_json(approval_request_id)
        append_openai_mcp_approval(
          content, provider_name, item_id, approval_id, name, arguments, id_generator,
        )
      }
      {
        "type": "mcp_approval_request",
        "id": String(item_id),
        "name": String(name),
        "arguments": arguments,
        ..
      } =>
        append_openai_mcp_approval(
          content, provider_name, item_id, item_id, name, arguments, id_generator,
        )
      {
        "type": "compaction",
        "id": String(item_id),
        "encrypted_content": encrypted_content,
        ..
      } =>
        content.push(
          @provider.GeneratedContent::custom(
            kind="openai.compaction",
            provider_metadata=openai_responses_item_metadata(
              provider_name,
              item_id,
              extra_fields={
                "type": "compaction",
                "encryptedContent": encrypted_content,
              },
            ),
          ),
        )
      { "type": "compaction", "id": String(item_id), .. } =>
        content.push(
          @provider.GeneratedContent::custom(
            kind="openai.compaction",
            provider_metadata=openai_responses_item_metadata(
              provider_name,
              item_id,
              extra_fields={ "type": "compaction" },
            ),
          ),
        )
      _ => ()
    }
  }
  let mapped_content : Array[@provider.GeneratedContent] = []
  for part in content {
    match part {
      @provider.GeneratedToolCallOutput(call) =>
        mapped_content.push(
          @provider.GeneratedContent::tool_call(
            @provider.ToolCall::new(
              id=call.id,
              name=tool_name_mapping.to_custom_tool_name(call.name),
              arguments=call.arguments,
              provider_executed=call.provider_executed,
              dynamic=call.dynamic,
              provider_metadata=call.provider_metadata,
            ),
          ),
        )
      @provider.GeneratedToolResultOutput(result) =>
        mapped_content.push(
          @provider.GeneratedContent::tool_result(
            @provider.ToolResult::new(
              tool_call_id=result.tool_call_id,
              tool_name=tool_name_mapping.to_custom_tool_name(result.tool_name),
              result=result.result,
              is_error=result.is_error,
              preliminary=result.preliminary,
              dynamic=result.dynamic,
              provider_metadata=result.provider_metadata,
            ),
          ),
        )
      other => mapped_content.push(other)
    }
  }
  (mapped_content, has_function_call)
}

///|
fn openai_responses_finish_reason(
  json : Json,
  has_function_call : Bool,
) -> @provider.FinishReason {
  let reason = match json {
    { "incomplete_details": { "reason": String(value), .. }, .. } => value
    _ => ""
  }
  if (match json {
      { "status": "failed", .. } => true
      _ => false
    }) {
    @provider.Error
  } else if reason == "max_output_tokens" {
    @provider.Length
  } else if reason == "content_filter" {
    @provider.ContentFilter
  } else if has_function_call {
    @provider.ToolCalls
  } else if reason == "" {
    @provider.Stop
  } else {
    @provider.Unknown(reason)
  }
}

///|
/// Decode an official OpenAI Responses response, including hosted tools.
pub fn decode_openai_responses_response(
  json : Json,
  provider_name? : String = "openai.responses",
  tool_name_mapping? : @provider_utils.ToolNameMapping,
  id_generator? : @provider_utils.IdGenerator,
) -> @provider.ChatResponse raise {
  if openai_responses_response_error(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI Responses request failed: \{message}",
      data=json,
    )
  }
  let output = match json {
    { "output": Array(items), .. } => items
    { "incomplete_details": { "reason": String(reason), .. }, .. } =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Responses returned no output (\{reason})",
        data=json,
      )
    { "status": String(status), .. } =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Responses returned no output (\{status})",
        data=json,
      )
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Responses returned no output",
        data=json,
      )
  }
  for item in output {
    match item {
      { "type": "computer_call", "call_id": String(_), .. } => {
        let _ = openai_responses_computer_call_input(item)
      }
      _ => ()
    }
  }
  let (content, has_function_call) = openai_responses_output_content(
    output,
    provider_name,
    tool_name_mapping.unwrap_or(@provider_utils.ToolNameMapping::identity()),
    id_generator.unwrap_or(@provider_utils.generate_id),
  )
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => openai_responses_usage(value)
    _ => @provider.Usage::zero()
  }
  let response_metadata = @provider.ResponseMetadata::from_json(json)
  let provider_metadata = @provider.merge_provider_metadata(
    @provider_utils.provider_metadata_from_json(json, provider_name),
    openai_responses_metadata(json, provider_name),
  )
  @provider.ChatResponse::from_content(
    content,
    usage,
    openai_responses_finish_reason(json, has_function_call),
  ).with_diagnostics(
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

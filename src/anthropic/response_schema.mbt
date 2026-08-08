///|
fn anthropic_response_field_error(path : String, message : String) -> String? {
  Some(path + ": " + message)
}

///|
fn anthropic_optional_string(value : Json?) -> Bool {
  match value {
    None | Some(Null) | Some(String(_)) => true
    _ => false
  }
}

///|
fn anthropic_optional_number(value : Json?) -> Bool {
  match value {
    None | Some(Null) | Some(Number(_)) => true
    _ => false
  }
}

///|
fn anthropic_string_or_null(value : Json?) -> Bool {
  match value {
    Some(Null) | Some(String(_)) => true
    _ => false
  }
}

///|
fn anthropic_number_or_null(value : Json?) -> Bool {
  match value {
    Some(Null) | Some(Number(_)) => true
    _ => false
  }
}

///|
fn anthropic_optional_object(value : Json?) -> Bool {
  match value {
    None | Some(Null) | Some(Object(_)) => true
    _ => false
  }
}

///|
fn anthropic_required_bool(value : Json?) -> Bool {
  match value {
    Some(True) | Some(False) => true
    _ => false
  }
}

///|
fn anthropic_usage_iteration_type(value : Json?) -> Bool {
  match value {
    Some(String("compaction"))
    | Some(String("message"))
    | Some(String("advisor_message"))
    | Some(String("fallback_message")) => true
    _ => false
  }
}

///|
fn anthropic_response_caller_error(
  value : Json?,
  path : String,
  allow_20250825 : Bool,
) -> String? {
  match value {
    None => None
    Some({ "type": "direct", .. }) => None
    Some({ "type": "code_execution_20250825", "tool_id": String(_), .. }) if allow_20250825 =>
      None
    Some({ "type": "code_execution_20260120", "tool_id": String(_), .. }) =>
      None
    _ =>
      anthropic_response_field_error(
        path, "must be a supported Anthropic tool caller",
      )
  }
}

///|
fn anthropic_response_citation_error(value : Json, path : String) -> String? {
  match value {
    {
      "type": "web_search_result_location",
      "cited_text": String(_),
      "url": String(_),
      "title": String(_),
      "encrypted_index": String(_),
      ..
    } => None
    {
      "type": "page_location",
      "cited_text": String(_),
      "document_index": Number(_),
      "document_title": String(_)
      | Null,
      "start_page_number": Number(_),
      "end_page_number": Number(_),
      ..
    } => None
    {
      "type": "char_location",
      "cited_text": String(_),
      "document_index": Number(_),
      "document_title": String(_)
      | Null,
      "start_char_index": Number(_),
      "end_char_index": Number(_),
      ..
    } => None
    _ =>
      anthropic_response_field_error(path, "must be a valid Anthropic citation")
  }
}

///|
fn anthropic_response_citations_error(value : Json?, path : String) -> String? {
  match value {
    None => None
    Some(Array(citations)) => {
      for index, citation in citations {
        if anthropic_response_citation_error(
            citation,
            path + "[" + index.to_string() + "]",
          )
          is Some(error) {
          return Some(error)
        }
      }
      None
    }
    _ => anthropic_response_field_error(path, "must be an array")
  }
}

///|
fn anthropic_response_file_outputs_error(
  value : Json?,
  path : String,
  kind : String,
  required : Bool,
) -> String? {
  match value {
    None if !required => None
    Some(Array(outputs)) => {
      for index, output in outputs {
        if !(output is { "type": String(output_kind), "file_id": String(_), .. } &&
          output_kind == kind) {
          return anthropic_response_field_error(
            path + "[" + index.to_string() + "]",
            "must contain type \"" + kind + "\" and file_id",
          )
        }
      }
      None
    }
    _ => anthropic_response_field_error(path, "must be an array")
  }
}

///|
fn anthropic_response_web_fetch_error(value : Json, path : String) -> String? {
  match value {
    { "type": "web_fetch_tool_result_error", "error_code": String(_), .. } =>
      None
    {
      "type": "web_fetch_result",
      "url": String(_),
      "retrieved_at": String(_),
      "content": Object(document),
      ..
    } => {
      guard document.get("type") is Some(String("document")) else {
        return anthropic_response_field_error(
          path + ".content.type",
          "must be \"document\"",
        )
      }
      guard anthropic_string_or_null(document.get("title")) else {
        return anthropic_response_field_error(
          path + ".content.title",
          "must be a string or null",
        )
      }
      match document.get("citations") {
        None => ()
        Some({ "enabled": True | False, .. }) => ()
        _ =>
          return anthropic_response_field_error(
            path + ".content.citations",
            "must contain a boolean enabled field",
          )
      }
      match document.get("source") {
        Some(
          {
            "type": "base64",
            "media_type": "application/pdf",
            "data": String(_),
            ..
          }
        ) => None
        Some(
          { "type": "text", "media_type": "text/plain", "data": String(_), .. }
        ) => None
        _ =>
          anthropic_response_field_error(
            path + ".content.source",
            "must be a supported document source",
          )
      }
    }
    _ =>
      anthropic_response_field_error(path, "must be a valid web fetch result")
  }
}

///|
fn anthropic_response_web_search_error(value : Json, path : String) -> String? {
  match value {
    { "type": "web_search_tool_result_error", "error_code": String(_), .. } =>
      None
    Array(results) => {
      for index, result in results {
        guard result is Object(fields) else {
          return anthropic_response_field_error(
            path + "[" + index.to_string() + "]",
            "must be an object",
          )
        }
        if fields.get("type") != Some(Json::string("web_search_result")) ||
          !(fields.get("url") is Some(String(_))) ||
          !(fields.get("title") is Some(String(_))) ||
          !(fields.get("encrypted_content") is Some(String(_))) ||
          !anthropic_optional_string(fields.get("page_age")) {
          return anthropic_response_field_error(
            path + "[" + index.to_string() + "]",
            "must be a valid web search result",
          )
        }
      }
      None
    }
    _ =>
      anthropic_response_field_error(
        path, "must be web search results or an error result",
      )
  }
}

///|
fn anthropic_response_code_execution_error(
  value : Json,
  path : String,
) -> String? {
  match value {
    {
      "type": "code_execution_result",
      "stdout": String(_),
      "stderr": String(_),
      "return_code": Number(_),
      ..
    } =>
      anthropic_response_file_outputs_error(
        match value {
          Object(fields) => fields.get("content")
          _ => None
        },
        path + ".content",
        "code_execution_output",
        false,
      )
    {
      "type": "encrypted_code_execution_result",
      "encrypted_stdout": String(_),
      "stderr": String(_),
      "return_code": Number(_),
      ..
    } =>
      anthropic_response_file_outputs_error(
        match value {
          Object(fields) => fields.get("content")
          _ => None
        },
        path + ".content",
        "code_execution_output",
        false,
      )
    { "type": "code_execution_tool_result_error", "error_code": String(_), .. } =>
      None
    _ =>
      anthropic_response_field_error(
        path, "must be a valid code execution result",
      )
  }
}

///|
fn anthropic_response_bash_execution_error(
  value : Json,
  path : String,
) -> String? {
  match value {
    {
      "type": "bash_code_execution_result",
      "stdout": String(_),
      "stderr": String(_),
      "return_code": Number(_),
      ..
    } =>
      anthropic_response_file_outputs_error(
        match value {
          Object(fields) => fields.get("content")
          _ => None
        },
        path + ".content",
        "bash_code_execution_output",
        true,
      )
    {
      "type": "bash_code_execution_tool_result_error",
      "error_code": String(_),
      ..
    } => None
    _ =>
      anthropic_response_field_error(
        path, "must be a valid bash code execution result",
      )
  }
}

///|
fn anthropic_response_nullable_string_array(value : Json?) -> Bool {
  match value {
    Some(Null) => true
    Some(Array(values)) => values.all(value => value is String(_))
    _ => false
  }
}

///|
fn anthropic_response_text_editor_error(value : Json, path : String) -> String? {
  match value {
    {
      "type": "text_editor_code_execution_tool_result_error",
      "error_code": String(_),
      ..
    } => None
    {
      "type": "text_editor_code_execution_view_result",
      "content": String(_),
      "file_type": String(_),
      "num_lines": Number(_)
      | Null,
      "start_line": Number(_)
      | Null,
      "total_lines": Number(_)
      | Null,
      ..
    } => None
    {
      "type": "text_editor_code_execution_create_result",
      "is_file_update": True
      | False,
      ..
    } => None
    { "type": "text_editor_code_execution_str_replace_result", .. } => {
      guard value is Object(fields) else { return None }
      if !anthropic_response_nullable_string_array(fields.get("lines")) ||
        !anthropic_number_or_null(fields.get("new_lines")) ||
        !anthropic_number_or_null(fields.get("new_start")) ||
        !anthropic_number_or_null(fields.get("old_lines")) ||
        !anthropic_number_or_null(fields.get("old_start")) {
        return anthropic_response_field_error(
          path, "must be a valid text replacement result",
        )
      }
      None
    }
    _ =>
      anthropic_response_field_error(path, "must be a valid text editor result")
  }
}

///|
fn anthropic_response_tool_search_error(value : Json, path : String) -> String? {
  match value {
    { "type": "tool_search_tool_result_error", "error_code": String(_), .. } =>
      None
    {
      "type": "tool_search_tool_search_result",
      "tool_references": Array(references),
      ..
    } => {
      for index, reference in references {
        if !(reference
          is { "type": "tool_reference", "tool_name": String(_), .. }) {
          return anthropic_response_field_error(
            path + ".tool_references[" + index.to_string() + "]",
            "must be a tool reference",
          )
        }
      }
      None
    }
    _ =>
      anthropic_response_field_error(path, "must be a valid tool search result")
  }
}

///|
fn anthropic_response_advisor_error(value : Json, path : String) -> String? {
  match value {
    { "type": "advisor_result", "text": String(_), .. } => None
    { "type": "advisor_redacted_result", "encrypted_content": String(_), .. } =>
      None
    { "type": "advisor_tool_result_error", "error_code": String(_), .. } => None
    _ => anthropic_response_field_error(path, "must be a valid advisor result")
  }
}

///|
fn anthropic_response_mcp_result_error(value : Json, path : String) -> String? {
  guard value is Array(parts) else {
    return anthropic_response_field_error(path, "must be an array")
  }
  for index, part in parts {
    match part {
      String(_) | { "type": "text", "text": String(_), .. } => ()
      _ =>
        return anthropic_response_field_error(
          path + "[" + index.to_string() + "]",
          "must be text",
        )
    }
  }
  None
}

///|
fn anthropic_response_content_block_error(
  value : Json,
  path : String,
) -> String? {
  guard value is Object(fields) else {
    return anthropic_response_field_error(path, "must be an object")
  }
  let kind = match fields.get("type") {
    Some(String(value)) => value
    _ =>
      return anthropic_response_field_error(path + ".type", "must be a string")
  }
  match kind {
    "text" => {
      guard fields.get("text") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".text",
          "must be a string",
        )
      }
      anthropic_response_citations_error(
        fields.get("citations"),
        path + ".citations",
      )
    }
    "thinking" =>
      if fields.get("thinking") is Some(String(_)) &&
        fields.get("signature") is Some(String(_)) {
        None
      } else {
        anthropic_response_field_error(
          path, "thinking blocks require thinking and signature strings",
        )
      }
    "redacted_thinking" =>
      if fields.get("data") is Some(String(_)) {
        None
      } else {
        anthropic_response_field_error(path + ".data", "must be a string")
      }
    "compaction" =>
      if fields.get("content") is Some(String(_)) {
        None
      } else {
        anthropic_response_field_error(path + ".content", "must be a string")
      }
    "tool_use" => {
      if !(fields.get("id") is Some(String(_))) ||
        !(fields.get("name") is Some(String(_))) ||
        fields.get("input") is None {
        return anthropic_response_field_error(
          path, "tool_use blocks require id, name, and input",
        )
      }
      anthropic_response_caller_error(
        fields.get("caller"),
        path + ".caller",
        true,
      )
    }
    "server_tool_use" => {
      if !(fields.get("id") is Some(String(_))) ||
        !(fields.get("name") is Some(String(_))) ||
        !anthropic_optional_object(fields.get("input")) {
        return anthropic_response_field_error(
          path, "server_tool_use blocks require id, name, and object input",
        )
      }
      anthropic_response_caller_error(
        fields.get("caller"),
        path + ".caller",
        false,
      )
    }
    "mcp_tool_use" =>
      if fields.get("id") is Some(String(_)) &&
        fields.get("name") is Some(String(_)) &&
        fields.get("input") is Some(_) &&
        fields.get("server_name") is Some(String(_)) {
        None
      } else {
        anthropic_response_field_error(
          path, "mcp_tool_use blocks require id, name, input, and server_name",
        )
      }
    "mcp_tool_result" => {
      if !(fields.get("tool_use_id") is Some(String(_))) ||
        !anthropic_required_bool(fields.get("is_error")) {
        return anthropic_response_field_error(
          path, "mcp_tool_result blocks require tool_use_id and is_error",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_mcp_result_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "web_fetch_tool_result" => {
      guard fields.get("tool_use_id") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".tool_use_id",
          "must be a string",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_web_fetch_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "web_search_tool_result" => {
      guard fields.get("tool_use_id") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".tool_use_id",
          "must be a string",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_web_search_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "code_execution_tool_result" => {
      guard fields.get("tool_use_id") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".tool_use_id",
          "must be a string",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_code_execution_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "bash_code_execution_tool_result" => {
      guard fields.get("tool_use_id") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".tool_use_id",
          "must be a string",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_bash_execution_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "text_editor_code_execution_tool_result" => {
      guard fields.get("tool_use_id") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".tool_use_id",
          "must be a string",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_text_editor_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "tool_search_tool_result" => {
      guard fields.get("tool_use_id") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".tool_use_id",
          "must be a string",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_tool_search_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "advisor_tool_result" => {
      guard fields.get("tool_use_id") is Some(String(_)) else {
        return anthropic_response_field_error(
          path + ".tool_use_id",
          "must be a string",
        )
      }
      match fields.get("content") {
        Some(content) =>
          anthropic_response_advisor_error(content, path + ".content")
        None => anthropic_response_field_error(path + ".content", "is required")
      }
    }
    "fallback" => None
    _ =>
      anthropic_response_field_error(
        path + ".type",
        "unsupported Anthropic content block type \"" + kind + "\"",
      )
  }
}

///|
fn anthropic_response_usage_error(value : Json?, path : String) -> String? {
  guard value is Some(Object(fields)) else {
    return anthropic_response_field_error(path, "must be an object")
  }
  if !(fields.get("input_tokens") is Some(Number(_))) ||
    !(fields.get("output_tokens") is Some(Number(_))) {
    return anthropic_response_field_error(
      path, "must contain numeric input_tokens and output_tokens",
    )
  }
  if !anthropic_optional_number(fields.get("cache_creation_input_tokens")) ||
    !anthropic_optional_number(fields.get("cache_read_input_tokens")) {
    return anthropic_response_field_error(
      path, "cache token counts must be numbers or null",
    )
  }
  match fields.get("output_tokens_details") {
    None | Some(Null) => ()
    Some(Object(details)) =>
      if !anthropic_optional_number(details.get("thinking_tokens")) {
        return anthropic_response_field_error(
          path + ".output_tokens_details.thinking_tokens",
          "must be a number or null",
        )
      }
    _ =>
      return anthropic_response_field_error(
        path + ".output_tokens_details",
        "must be an object or null",
      )
  }
  match fields.get("iterations") {
    None | Some(Null) => None
    Some(Array(iterations)) => {
      for index, iteration in iterations {
        guard iteration is Object(item) else {
          return anthropic_response_field_error(
            path + ".iterations[" + index.to_string() + "]",
            "must be an object",
          )
        }
        if !anthropic_usage_iteration_type(item.get("type")) ||
          !anthropic_optional_string(item.get("model")) ||
          !(item.get("input_tokens") is Some(Number(_))) ||
          !(item.get("output_tokens") is Some(Number(_))) ||
          !anthropic_optional_number(item.get("cache_creation_input_tokens")) ||
          !anthropic_optional_number(item.get("cache_read_input_tokens")) {
          return anthropic_response_field_error(
            path + ".iterations[" + index.to_string() + "]",
            "must be a valid Anthropic usage iteration",
          )
        }
      }
      None
    }
    _ =>
      anthropic_response_field_error(path + ".iterations", "must be an array")
  }
}

///|
fn anthropic_response_container_error(value : Json?, path : String) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      if !(fields.get("expires_at") is Some(String(_))) ||
        !(fields.get("id") is Some(String(_))) {
        return anthropic_response_field_error(
          path, "must contain expires_at and id strings",
        )
      }
      match fields.get("skills") {
        None | Some(Null) => None
        Some(Array(skills)) => {
          for index, skill in skills {
            if !(skill
              is {
                "type": "anthropic"
                | "custom",
                "skill_id": String(_),
                "version": String(_),
                ..
              }) {
              return anthropic_response_field_error(
                path + ".skills[" + index.to_string() + "]",
                "must be a valid skill reference",
              )
            }
          }
          None
        }
        _ =>
          anthropic_response_field_error(path + ".skills", "must be an array")
      }
    }
    _ => anthropic_response_field_error(path, "must be an object or null")
  }
}

///|
fn anthropic_response_context_error(value : Json?, path : String) -> String? {
  match value {
    None | Some(Null) => None
    Some({ "applied_edits": Array(edits), .. }) => {
      for index, edit in edits {
        let valid = match edit {
          {
            "type": "clear_tool_uses_20250919",
            "cleared_tool_uses": Number(_),
            "cleared_input_tokens": Number(_),
            ..
          } => true
          {
            "type": "clear_thinking_20251015",
            "cleared_thinking_turns": Number(_),
            "cleared_input_tokens": Number(_),
            ..
          } => true
          { "type": "compact_20260112", .. } => true
          _ => false
        }
        if !valid {
          return anthropic_response_field_error(
            path + ".applied_edits[" + index.to_string() + "]",
            "must be a valid context-management edit",
          )
        }
      }
      None
    }
    _ =>
      anthropic_response_field_error(
        path, "must contain an applied_edits array",
      )
  }
}

///|
fn anthropic_response_stop_details_error(
  value : Json?,
  path : String,
) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) =>
      if fields.get("type") is Some(String(_)) &&
        anthropic_optional_string(fields.get("category")) &&
        anthropic_optional_string(fields.get("explanation")) &&
        anthropic_optional_string(fields.get("recommended_model")) {
        None
      } else {
        anthropic_response_field_error(
          path, "must be a valid stop-details object",
        )
      }
    _ => anthropic_response_field_error(path, "must be an object or null")
  }
}

///|
fn anthropic_messages_response_validation_error(json : Json) -> String? {
  guard json is Object(fields) else {
    return anthropic_response_field_error("$", "must be an object")
  }
  guard fields.get("type") == Some(Json::string("message")) else {
    return anthropic_response_field_error(
      "$.type", "must be the literal \"message\"",
    )
  }
  if !anthropic_optional_string(fields.get("id")) {
    return anthropic_response_field_error("$.id", "must be a string or null")
  }
  if !anthropic_optional_string(fields.get("model")) {
    return anthropic_response_field_error("$.model", "must be a string or null")
  }
  guard fields.get("content") is Some(Array(blocks)) else {
    return anthropic_response_field_error("$.content", "must be an array")
  }
  for index, block in blocks {
    if anthropic_response_content_block_error(
        block,
        "$.content[" + index.to_string() + "]",
      )
      is Some(error) {
      return Some(error)
    }
  }
  if !anthropic_optional_string(fields.get("stop_reason")) {
    return anthropic_response_field_error(
      "$.stop_reason", "must be a string or null",
    )
  }
  if !anthropic_optional_string(fields.get("stop_sequence")) {
    return anthropic_response_field_error(
      "$.stop_sequence", "must be a string or null",
    )
  }
  if anthropic_response_stop_details_error(
      fields.get("stop_details"),
      "$.stop_details",
    )
    is Some(error) {
    return Some(error)
  }
  if anthropic_response_usage_error(fields.get("usage"), "$.usage")
    is Some(error) {
    return Some(error)
  }
  if anthropic_response_container_error(fields.get("container"), "$.container")
    is Some(error) {
    return Some(error)
  }
  anthropic_response_context_error(
    fields.get("context_management"),
    "$.context_management",
  )
}

///|
/// Validate the successful HTTP Messages response before normalization. The
/// decoder itself stays permissive so focused mapping tests can use partial
/// fixtures, while the provider boundary matches the AI SDK response schema.
fn validate_anthropic_messages_response(json : Json) -> Unit raise {
  if anthropic_messages_response_validation_error(json) is Some(error) {
    raise @provider.InvalidResponseDataError(
      message="Invalid Anthropic Messages response: " + error,
      data=json,
    )
  }
}

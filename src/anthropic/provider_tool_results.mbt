///|
fn anthropic_provider_tool_result_warning(
  warnings : Array[@provider.Warning],
  tool_name : String,
  output_type : String,
) -> Unit {
  warnings.push(
    @provider.Warning::Other(
      message="provider executed tool result output type \{output_type} for tool \{tool_name} is not supported",
    ),
  )
}

///|
fn anthropic_provider_tool_error_code(
  value : Json,
  fallback : String,
) -> String {
  match value {
    { "errorCode": String(code), .. } | { "error_code": String(code), .. } =>
      code
    _ => fallback
  }
}

///|
fn anthropic_code_execution_error_result(
  result : @provider.LanguageModelV4ToolResultPart,
  value : Json?,
) -> Json {
  let error_value = value.unwrap_or(Json::empty_object())
  let error_code = anthropic_provider_tool_error_code(error_value, "unknown")
  match error_value {
    { "type": "code_execution_tool_result_error", .. } =>
      {
        "type": "code_execution_tool_result",
        "tool_use_id": result.tool_call_id,
        "content": {
          "type": "code_execution_tool_result_error",
          "error_code": error_code,
        },
      }
    _ =>
      {
        "type": "bash_code_execution_tool_result",
        "tool_use_id": result.tool_call_id,
        "content": {
          "type": "bash_code_execution_tool_result_error",
          "error_code": error_code,
        },
      }
  }
}

///|
fn anthropic_code_execution_standard_result(
  result : @provider.LanguageModelV4ToolResultPart,
  value : Json,
) -> Json {
  let fields = match value {
    Object(fields) => fields
    _ => Map([])
  }
  let content = fields.get("content").unwrap_or(Json::array([]))
  let output : Map[String, Json] = Map([
    ("type", fields.get("type").unwrap_or("code_execution_result")),
    ("stderr", fields.get("stderr").unwrap_or("")),
    ("return_code", fields.get("return_code").unwrap_or(0)),
    ("content", content),
  ])
  if fields.get("encrypted_stdout") is Some(encrypted_stdout) {
    output["encrypted_stdout"] = encrypted_stdout
  } else {
    output["stdout"] = fields.get("stdout").unwrap_or("")
  }
  {
    "type": "code_execution_tool_result",
    "tool_use_id": result.tool_call_id,
    "content": Json::object(output),
  }
}

///|
fn anthropic_v4_code_execution_result(
  result : @provider.LanguageModelV4ToolResultPart,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match result.output {
    @provider.V4ToolResultErrorJson(value~, ..) =>
      Some(anthropic_code_execution_error_result(result, Some(value)))
    @provider.V4ToolResultErrorText(..) =>
      Some(anthropic_code_execution_error_result(result, None))
    @provider.V4ToolResultJsonOutput(value~, ..) => {
      guard value is { "type": String(kind), .. } else {
        warnings.push(
          @provider.Warning::Other(
            message="provider executed tool result output value is not a valid code execution result for tool \{result.tool_name}",
          ),
        )
        return None
      }
      if kind == "code_execution_result" {
        @provider_utils.validate_json_schema(
          anthropic_code_execution_result_schema(false),
          value,
        )
        Some(anthropic_code_execution_standard_result(result, value))
      } else if kind == "encrypted_code_execution_result" {
        @provider_utils.validate_json_schema(
          anthropic_code_execution_output_schema(true),
          value,
        )
        Some(anthropic_code_execution_standard_result(result, value))
      } else {
        @provider_utils.validate_json_schema(
          anthropic_code_execution_output_schema(false),
          value,
        )
        let block_type = if kind == "bash_code_execution_result" ||
          kind == "bash_code_execution_tool_result_error" {
          "bash_code_execution_tool_result"
        } else {
          "text_editor_code_execution_tool_result"
        }
        Some({
          "type": block_type,
          "tool_use_id": result.tool_call_id,
          "content": value,
        })
      }
    }
    output => {
      let output_type = match output {
        @provider.V4ToolResultTextOutput(..) => "text"
        @provider.V4ToolResultExecutionDenied(..) => "execution-denied"
        @provider.V4ToolResultContentOutput(..) => "content"
        _ => "unknown"
      }
      anthropic_provider_tool_result_warning(
        warnings,
        result.tool_name,
        output_type,
      )
      None
    }
  }
}

///|
fn anthropic_v4_web_fetch_result(
  result : @provider.LanguageModelV4ToolResultPart,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match result.output {
    @provider.V4ToolResultErrorJson(value~, ..) =>
      Some({
        "type": "web_fetch_tool_result",
        "tool_use_id": result.tool_call_id,
        "content": {
          "type": "web_fetch_tool_result_error",
          "error_code": anthropic_provider_tool_error_code(value, "unavailable"),
        },
      })
    @provider.V4ToolResultJsonOutput(value~, ..) => {
      @provider_utils.validate_json_schema(
        anthropic_web_fetch_output_schema(),
        value,
      )
      guard value
        is {
          "url": url,
          "content": Object(document),
          "retrievedAt": retrieved_at,
          ..
        } else {
        return None
      }
      let source = document.get("source").unwrap()
      let content : Map[String, Json] = Map([
        ("type", Json::string("document")),
        ("title", document.get("title").unwrap_or(Json::null())),
        ("source", anthropic_wire_json(source)),
      ])
      if document.get("citations") is Some(citations) {
        content["citations"] = citations
      }
      Some({
        "type": "web_fetch_tool_result",
        "tool_use_id": result.tool_call_id,
        "content": {
          "type": "web_fetch_result",
          "url": url,
          "retrieved_at": retrieved_at,
          "content": Json::object(content),
        },
      })
    }
    output => {
      let output_type = if output is @provider.V4ToolResultErrorText(..) {
        "error-text"
      } else {
        "non-json"
      }
      anthropic_provider_tool_result_warning(
        warnings,
        result.tool_name,
        output_type,
      )
      None
    }
  }
}

///|
fn anthropic_v4_web_search_result(
  result : @provider.LanguageModelV4ToolResultPart,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match result.output {
    @provider.V4ToolResultErrorJson(value~, ..) =>
      Some({
        "type": "web_search_tool_result",
        "tool_use_id": result.tool_call_id,
        "content": {
          "type": "web_search_tool_result_error",
          "error_code": anthropic_provider_tool_error_code(value, "unavailable"),
        },
      })
    @provider.V4ToolResultJsonOutput(value~, ..) => {
      @provider_utils.validate_json_schema(
        anthropic_web_search_output_schema(),
        value,
      )
      Some({
        "type": "web_search_tool_result",
        "tool_use_id": result.tool_call_id,
        "content": anthropic_wire_json(value),
      })
    }
    output => {
      let output_type = if output is @provider.V4ToolResultErrorText(..) {
        "error-text"
      } else {
        "non-json"
      }
      anthropic_provider_tool_result_warning(
        warnings,
        result.tool_name,
        output_type,
      )
      None
    }
  }
}

///|
fn anthropic_v4_tool_search_result(
  result : @provider.LanguageModelV4ToolResultPart,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match result.output {
    @provider.V4ToolResultJsonOutput(value~, ..) => {
      @provider_utils.validate_json_schema(
        anthropic_tool_search_output_schema(),
        value,
      )
      let references : Array[Json] = match value {
        Array(items) =>
          [
            for item in items => {
              match item {
                { "type": String(kind), "toolName": String(name), .. } =>
                  { "type": kind, "tool_name": name }
                _ => Json::empty_object()
              }
            }
          ]
        _ => []
      }
      Some({
        "type": "tool_search_tool_result",
        "tool_use_id": result.tool_call_id,
        "content": {
          "type": "tool_search_tool_search_result",
          "tool_references": Json::array(references),
        },
      })
    }
    output => {
      let output_type = if output is @provider.V4ToolResultErrorJson(..) {
        "error-json"
      } else {
        "non-json"
      }
      anthropic_provider_tool_result_warning(
        warnings,
        result.tool_name,
        output_type,
      )
      None
    }
  }
}

///|
fn anthropic_is_special_provider_tool_result(name : String) -> Bool {
  name == "code_execution" ||
  name == "web_fetch" ||
  name == "web_search" ||
  name == "tool_search_tool_regex" ||
  name == "tool_search_tool_bm25"
}

///|
fn anthropic_v4_provider_tool_result(
  result : @provider.LanguageModelV4ToolResultPart,
  provider_tool_name : String,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match provider_tool_name {
    "code_execution" => anthropic_v4_code_execution_result(result, warnings)
    "web_fetch" => anthropic_v4_web_fetch_result(result, warnings)
    "web_search" => anthropic_v4_web_search_result(result, warnings)
    "tool_search_tool_regex" | "tool_search_tool_bm25" =>
      anthropic_v4_tool_search_result(result, warnings)
    _ => None
  }
}

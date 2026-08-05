///|
priv struct AnthropicPreparedTools {
  tools : Array[Json]
  beta_features : Array[String]
}

///|
fn anthropic_tool_option(
  options : Map[String, Json],
  name : String,
  alternate_name : String,
) -> Json? {
  match options.get(name) {
    Some(value) => Some(value)
    None => options.get(alternate_name)
  }
}

///|
fn anthropic_tool_bool_option(
  options : Map[String, Json],
  name : String,
  alternate_name : String,
) -> Bool? {
  match anthropic_tool_option(options, name, alternate_name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn anthropic_function_tool(
  name : String,
  description : String?,
  input_schema : Json,
  input_examples : Array[Json],
  strict : Bool?,
  provider_options : Map[String, Json],
  supports_structured_output : Bool,
  supports_strict_tools : Bool,
  default_eager_input_streaming : Bool,
  warnings : Array[@provider.Warning],
  beta_features : Array[String],
) -> Json {
  let fields : Map[String, Json] = Map([("name", Json::string(name))])
  if description is Some(value) {
    fields["description"] = Json::string(value)
  }
  fields["input_schema"] = input_schema
  let mut eager_input_streaming = default_eager_input_streaming
  let mut has_allowed_callers = false
  match provider_options.get("anthropic") {
    Some(Object(options)) => {
      if anthropic_tool_option(options, "cacheControl", "cache_control")
        is Some(value) {
        fields["cache_control"] = anthropic_wire_json(value)
      }
      if anthropic_tool_bool_option(
          options, "eagerInputStreaming", "eager_input_streaming",
        )
        is Some(value) {
        eager_input_streaming = value
      }
      if anthropic_tool_bool_option(options, "deferLoading", "defer_loading")
        is Some(value) {
        fields["defer_loading"] = Json::boolean(value)
      }
      if anthropic_tool_option(options, "allowedCallers", "allowed_callers")
        is Some(Array(values)) {
        fields["allowed_callers"] = Json::array(values)
        has_allowed_callers = true
      }
    }
    _ => ()
  }
  match strict {
    Some(value) if supports_strict_tools =>
      fields["strict"] = Json::boolean(value)
    Some(value) =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="strict",
          details="Tool '\{name}' has strict: \{value}, but strict mode is not supported by this provider; strict was ignored.",
        ),
      )
    None => ()
  }
  if eager_input_streaming {
    fields["eager_input_streaming"] = Json::boolean(true)
  }
  if input_examples.length() > 0 {
    fields["input_examples"] = Json::array(input_examples)
  }
  if supports_structured_output {
    append_unique_beta(beta_features, "structured-outputs-2025-11-13")
  }
  if input_examples.length() > 0 || has_allowed_callers {
    append_unique_beta(beta_features, "advanced-tool-use-2025-11-20")
  }
  Json::object(fields)
}

///|
fn anthropic_provider_tool_fields(
  args : Json,
  id : String,
) -> Map[String, Json] raise {
  match anthropic_wire_json(args) {
    Object(fields) => fields
    _ => fail("Anthropic provider tool \{id} arguments must be a JSON object")
  }
}

///|
fn anthropic_copy_provider_tool_fields(
  source : Map[String, Json],
  target : Map[String, Json],
  names : Array[String],
) -> Unit {
  for name in names {
    if source.get(name) is Some(value) {
      target[name] = value
    }
  }
}

///|
fn anthropic_provider_tool_json(
  id : String,
  args : Json,
  wire_type : String,
  wire_name : String,
  fields : Array[String],
  required_fields? : Array[String] = [],
) -> Json raise {
  let source = anthropic_provider_tool_fields(args, id)
  for field in required_fields {
    guard source.get(field) is Some(_) else {
      fail("Anthropic provider tool \{id} requires argument '\{field}'")
    }
  }
  let output : Map[String, Json] = Map([
    ("type", Json::string(wire_type)),
    ("name", Json::string(wire_name)),
  ])
  anthropic_copy_provider_tool_fields(source, output, fields)
  Json::object(output)
}

///|
fn anthropic_provider_tool(
  id : String,
  args : Json,
  warnings : Array[@provider.Warning],
  beta_features : Array[String],
) -> Json? raise {
  match id {
    "anthropic.code_execution_20250522" => {
      append_unique_beta(beta_features, "code-execution-2025-05-22")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "code_execution_20250522",
          "code_execution",
          [],
        ),
      )
    }
    "anthropic.code_execution_20250825" => {
      append_unique_beta(beta_features, "code-execution-2025-08-25")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "code_execution_20250825",
          "code_execution",
          [],
        ),
      )
    }
    "anthropic.code_execution_20260120" =>
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "code_execution_20260120",
          "code_execution",
          [],
        ),
      )
    "anthropic.computer_20241022" => {
      append_unique_beta(beta_features, "computer-use-2024-10-22")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "computer_20241022",
          "computer",
          ["display_width_px", "display_height_px", "display_number"],
          required_fields=["display_width_px", "display_height_px"],
        ),
      )
    }
    "anthropic.computer_20250124" => {
      append_unique_beta(beta_features, "computer-use-2025-01-24")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "computer_20250124",
          "computer",
          ["display_width_px", "display_height_px", "display_number"],
          required_fields=["display_width_px", "display_height_px"],
        ),
      )
    }
    "anthropic.computer_20251124" => {
      append_unique_beta(beta_features, "computer-use-2025-11-24")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "computer_20251124",
          "computer",
          [
            "display_width_px", "display_height_px", "display_number", "enable_zoom",
          ],
          required_fields=["display_width_px", "display_height_px"],
        ),
      )
    }
    "anthropic.text_editor_20241022" => {
      append_unique_beta(beta_features, "computer-use-2024-10-22")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "text_editor_20241022",
          "str_replace_editor",
          [],
        ),
      )
    }
    "anthropic.text_editor_20250124" => {
      append_unique_beta(beta_features, "computer-use-2025-01-24")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "text_editor_20250124",
          "str_replace_editor",
          [],
        ),
      )
    }
    "anthropic.text_editor_20250429" => {
      append_unique_beta(beta_features, "computer-use-2025-01-24")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "text_editor_20250429",
          "str_replace_based_edit_tool",
          [],
        ),
      )
    }
    "anthropic.text_editor_20250728" =>
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "text_editor_20250728",
          "str_replace_based_edit_tool",
          ["max_characters"],
        ),
      )
    "anthropic.bash_20241022" => {
      append_unique_beta(beta_features, "computer-use-2024-10-22")
      Some(anthropic_provider_tool_json(id, args, "bash_20241022", "bash", []))
    }
    "anthropic.bash_20250124" => {
      append_unique_beta(beta_features, "computer-use-2025-01-24")
      Some(anthropic_provider_tool_json(id, args, "bash_20250124", "bash", []))
    }
    "anthropic.memory_20250818" => {
      append_unique_beta(beta_features, "context-management-2025-06-27")
      Some(
        anthropic_provider_tool_json(id, args, "memory_20250818", "memory", []),
      )
    }
    "anthropic.web_fetch_20250910" => {
      append_unique_beta(beta_features, "web-fetch-2025-09-10")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "web_fetch_20250910",
          "web_fetch",
          [
            "max_uses", "allowed_domains", "blocked_domains", "citations", "max_content_tokens",
          ],
        ),
      )
    }
    "anthropic.web_fetch_20260209" => {
      append_unique_beta(beta_features, "code-execution-web-tools-2026-02-09")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "web_fetch_20260209",
          "web_fetch",
          [
            "max_uses", "allowed_domains", "blocked_domains", "citations", "max_content_tokens",
          ],
        ),
      )
    }
    "anthropic.web_search_20250305" =>
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "web_search_20250305",
          "web_search",
          ["max_uses", "allowed_domains", "blocked_domains", "user_location"],
        ),
      )
    "anthropic.web_search_20260209" => {
      append_unique_beta(beta_features, "code-execution-web-tools-2026-02-09")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "web_search_20260209",
          "web_search",
          ["max_uses", "allowed_domains", "blocked_domains", "user_location"],
        ),
      )
    }
    "anthropic.tool_search_regex_20251119" =>
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "tool_search_tool_regex_20251119",
          "tool_search_tool_regex",
          [],
        ),
      )
    "anthropic.tool_search_bm25_20251119" =>
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "tool_search_tool_bm25_20251119",
          "tool_search_tool_bm25",
          [],
        ),
      )
    "anthropic.advisor_20260301" => {
      append_unique_beta(beta_features, "advisor-tool-2026-03-01")
      Some(
        anthropic_provider_tool_json(
          id,
          args,
          "advisor_20260301",
          "advisor",
          ["model", "max_uses", "caching"],
          required_fields=["model"],
        ),
      )
    }
    _ => {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="provider-defined tool \{id}",
          details="Unknown Anthropic provider tool was ignored.",
        ),
      )
      None
    }
  }
}

///|
fn anthropic_provider_tool_names() -> Map[String, String] {
  Map([
    ("anthropic.code_execution_20250522", "code_execution"),
    ("anthropic.code_execution_20250825", "code_execution"),
    ("anthropic.code_execution_20260120", "code_execution"),
    ("anthropic.computer_20241022", "computer"),
    ("anthropic.computer_20250124", "computer"),
    ("anthropic.computer_20251124", "computer"),
    ("anthropic.text_editor_20241022", "str_replace_editor"),
    ("anthropic.text_editor_20250124", "str_replace_editor"),
    ("anthropic.text_editor_20250429", "str_replace_based_edit_tool"),
    ("anthropic.text_editor_20250728", "str_replace_based_edit_tool"),
    ("anthropic.bash_20241022", "bash"),
    ("anthropic.bash_20250124", "bash"),
    ("anthropic.memory_20250818", "memory"),
    ("anthropic.web_search_20250305", "web_search"),
    ("anthropic.web_search_20260209", "web_search"),
    ("anthropic.web_fetch_20250910", "web_fetch"),
    ("anthropic.web_fetch_20260209", "web_fetch"),
    ("anthropic.tool_search_regex_20251119", "tool_search_tool_regex"),
    ("anthropic.tool_search_bm25_20251119", "tool_search_tool_bm25"),
    ("anthropic.advisor_20260301", "advisor"),
  ])
}

///|
fn create_anthropic_tool_name_mapping(
  tools : Array[@provider.ToolDefinition],
) -> @provider_utils.ToolNameMapping {
  @provider_utils.create_tool_name_mapping(
    tools,
    anthropic_provider_tool_names(),
  )
}

///|
fn prepare_anthropic_tools(
  tools : Array[@provider.ToolDefinition],
  supports_structured_output : Bool,
  supports_strict_tools : Bool,
  default_eager_input_streaming : Bool,
  warnings : Array[@provider.Warning],
) -> AnthropicPreparedTools raise {
  let prepared : Array[Json] = []
  let beta_features : Array[String] = []
  for tool in tools {
    match tool {
      @provider.FunctionTool(
        name~,
        description~,
        input_schema~,
        input_examples~,
        strict~,
        provider_options~
      ) =>
        prepared.push(
          anthropic_function_tool(
            name, description, input_schema, input_examples, strict, provider_options,
            supports_structured_output, supports_strict_tools, default_eager_input_streaming,
            warnings, beta_features,
          ),
        )
      @provider.ProviderTool(id~, args~, ..) =>
        if anthropic_provider_tool(id, args, warnings, beta_features)
          is Some(value) {
          prepared.push(value)
        }
    }
  }
  { tools: prepared, beta_features }
}

///|
/// Create Anthropic's code execution tool dated 2025-05-22.
pub fn code_execution_20250522_tool(
  name? : String = "code_execution",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.code_execution_20250522",
    name~,
  )
}

///|
/// Create Anthropic's code execution tool dated 2025-08-25.
pub fn code_execution_20250825_tool(
  name? : String = "code_execution",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.code_execution_20250825",
    name~,
  )
}

///|
/// Create Anthropic's current code execution tool.
pub fn code_execution_20260120_tool(
  name? : String = "code_execution",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.code_execution_20260120",
    name~,
  )
}

///|
/// Create an Anthropic computer-use provider tool.
pub fn computer_20241022_tool(
  args : Json,
  name? : String = "computer",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.computer_20241022",
    name~,
    args~,
  )
}

///|
/// Create an Anthropic computer-use provider tool.
pub fn computer_20250124_tool(
  args : Json,
  name? : String = "computer",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.computer_20250124",
    name~,
    args~,
  )
}

///|
/// Create the current Anthropic computer-use provider tool.
pub fn computer_20251124_tool(
  args : Json,
  name? : String = "computer",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.computer_20251124",
    name~,
    args~,
  )
}

///|
/// Create an Anthropic text-editor provider tool.
pub fn text_editor_20241022_tool(
  name? : String = "str_replace_editor",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(id="anthropic.text_editor_20241022", name~)
}

///|
/// Create an Anthropic text-editor provider tool.
pub fn text_editor_20250124_tool(
  name? : String = "str_replace_editor",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(id="anthropic.text_editor_20250124", name~)
}

///|
/// Create an Anthropic text-editor provider tool.
pub fn text_editor_20250429_tool(
  name? : String = "str_replace_based_edit_tool",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(id="anthropic.text_editor_20250429", name~)
}

///|
/// Create the current Anthropic text-editor provider tool.
pub fn text_editor_20250728_tool(
  args? : Json = Json::empty_object(),
  name? : String = "str_replace_based_edit_tool",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.text_editor_20250728",
    name~,
    args~,
  )
}

///|
/// Create an Anthropic bash provider tool.
pub fn bash_20241022_tool(name? : String = "bash") -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(id="anthropic.bash_20241022", name~)
}

///|
/// Create an Anthropic bash provider tool.
pub fn bash_20250124_tool(name? : String = "bash") -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(id="anthropic.bash_20250124", name~)
}

///|
/// Create Anthropic's memory provider tool.
pub fn memory_20250818_tool(
  name? : String = "memory",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(id="anthropic.memory_20250818", name~)
}

///|
/// Create an Anthropic web-fetch provider tool.
pub fn web_fetch_20250910_tool(
  args? : Json = Json::empty_object(),
  name? : String = "web_fetch",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.web_fetch_20250910",
    name~,
    args~,
  )
}

///|
/// Create the current Anthropic web-fetch provider tool.
pub fn web_fetch_20260209_tool(
  args? : Json = Json::empty_object(),
  name? : String = "web_fetch",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.web_fetch_20260209",
    name~,
    args~,
  )
}

///|
/// Create an Anthropic web-search provider tool.
pub fn web_search_20250305_tool(
  args? : Json = Json::empty_object(),
  name? : String = "web_search",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.web_search_20250305",
    name~,
    args~,
  )
}

///|
/// Create the current Anthropic web-search provider tool.
pub fn web_search_20260209_tool(
  args? : Json = Json::empty_object(),
  name? : String = "web_search",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.web_search_20260209",
    name~,
    args~,
  )
}

///|
/// Create Anthropic's regex tool-search provider tool.
pub fn tool_search_regex_20251119_tool(
  name? : String = "tool_search_tool_regex",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.tool_search_regex_20251119",
    name~,
  )
}

///|
/// Create Anthropic's BM25 tool-search provider tool.
pub fn tool_search_bm25_20251119_tool(
  name? : String = "tool_search_tool_bm25",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.tool_search_bm25_20251119",
    name~,
  )
}

///|
/// Create Anthropic's advisor provider tool.
pub fn advisor_20260301_tool(
  args : Json,
  name? : String = "advisor",
) -> @provider.ToolDefinition {
  @provider.ToolDefinition::provider(
    id="anthropic.advisor_20260301",
    name~,
    args~,
  )
}

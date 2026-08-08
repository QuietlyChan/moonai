///|
priv struct AnthropicOptions {
  send_reasoning : Bool
  structured_output_mode : String
  thinking : AnthropicThinking?
  disable_parallel_tool_use : Bool?
  cache_control : Json?
  metadata_user_id : String?
  mcp_servers : Array[Json]
  container : Json?
  tool_streaming : Bool
  effort : String?
  task_budget : Json?
  speed : String?
  inference_geo : String?
  fallbacks : Json?
  beta_features : Array[String]
  context_management : Json?
}

///|
priv struct ParsedAnthropicOptions {
  options : AnthropicOptions
  warnings : Array[@provider.Warning]
  used_custom_provider_key : Bool
}

///|
priv struct AnthropicPreparedRequest {
  body : Json
  warnings : Array[@provider.Warning]
  beta_features : Array[String]
  tool_name_mapping : @provider_utils.ToolNameMapping
  mark_code_execution_dynamic : Bool
  uses_json_response_tool : Bool
  used_custom_provider_key : Bool
}

///|
fn anthropic_reserved_fields() -> Array[String] {
  [
    "model", "messages", "max_tokens", "stream", "system", "temperature", "top_p",
    "stop_sequences", "tools", "tool_choice", "output_config",
  ]
}

///|
fn resolve_anthropic_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> (@provider_utils.ProviderOptionsResolution, Bool) {
  let canonical = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name="anthropic.messages",
    reserved_fields=anthropic_reserved_fields(),
  )
  let custom = @provider_utils.resolve_provider_options(
    provider_options,
    provider_name~,
    reserved_fields=anthropic_reserved_fields(),
  )
  let provider_parts = [ for part in provider_name.split(".") => part ]
  let provider_options_name = if provider_parts.length() > 0 {
    provider_parts[0].trim().to_owned()
  } else {
    ""
  }
  let used_custom_provider_key = provider_options_name != "" &&
    provider_options_name != "anthropic" &&
    custom.namespace_key is Some(_)
  if canonical.namespace_key is Some(key) && custom.namespace_key == Some(key) {
    return (custom, used_custom_provider_key)
  }
  if canonical.namespace_key is Some(_) || custom.namespace_key is Some(_) {
    return (
      @provider_utils.merge_provider_options_resolutions(canonical, custom),
      used_custom_provider_key,
    )
  }
  (
    @provider_utils.resolve_provider_options(
      provider_options,
      provider_name~,
      aliases=["anthropic"],
      reserved_fields=anthropic_reserved_fields(),
    ),
    false,
  )
}

///|
fn invalid_anthropic_option(
  reader : @provider_utils.ProviderOptionsReader,
  feature : String,
  details : String,
) -> Unit {
  reader.add_warning(
    @provider.Warning::Compatibility(
      feature="providerOptions.\{feature}",
      details~,
    ),
  )
}

///|
fn parse_anthropic_thinking(
  reader : @provider_utils.ProviderOptionsReader,
) -> AnthropicThinking? {
  guard reader.take_object("thinking") is Some(value) else { return None }
  let json = Json::object(value)
  let kind = @provider_utils.json_string_field(json, "type").unwrap_or("")
  match kind {
    "adaptive" => {
      let display = match value.get("display") {
        Some(String("omitted")) => Some(AnthropicThinkingOmitted)
        Some(String("summarized")) => Some(AnthropicThinkingSummarized)
        Some(_) => {
          invalid_anthropic_option(
            reader, "thinking.display", "Expected omitted or summarized; the invalid value was ignored.",
          )
          None
        }
        None => None
      }
      Some(AnthropicThinkingAdaptive(display))
    }
    "enabled" => {
      let budget_tokens = match value.get("budgetTokens") {
        Some(Number(number, ..)) =>
          match @provider_utils.json_number_as_int(number) {
            Some(value) => Some(value)
            None => {
              invalid_anthropic_option(
                reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
              )
              None
            }
          }
        Some(_) => {
          invalid_anthropic_option(
            reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
          )
          None
        }
        None =>
          match value.get("budget_tokens") {
            Some(Number(number, ..)) => {
              reader.add_warning(
                @provider.Warning::Deprecated(
                  setting="providerOptions.thinking.budget_tokens",
                  message="Use 'providerOptions.thinking.budgetTokens'.",
                ),
              )
              match @provider_utils.json_number_as_int(number) {
                Some(value) => Some(value)
                None => {
                  invalid_anthropic_option(
                    reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
                  )
                  None
                }
              }
            }
            Some(_) => {
              invalid_anthropic_option(
                reader, "thinking.budgetTokens", "Expected an integer; the invalid value was ignored.",
              )
              None
            }
            None => None
          }
      }
      Some(AnthropicThinkingEnabled(budget_tokens))
    }
    "disabled" => Some(AnthropicThinkingDisabled)
    _ => {
      invalid_anthropic_option(
        reader, "thinking.type", "Expected adaptive, enabled, or disabled; thinking was ignored.",
      )
      None
    }
  }
}

///|
fn parse_metadata_user_id(
  reader : @provider_utils.ProviderOptionsReader,
) -> String? {
  guard reader.take_object("metadata") is Some(metadata) else { return None }
  match metadata.get("userId") {
    Some(String(value)) => Some(value)
    Some(_) => {
      invalid_anthropic_option(
        reader, "metadata.userId", "Expected a string; metadata.userId was ignored.",
      )
      None
    }
    None =>
      match metadata.get("user_id") {
        Some(String(value)) => {
          reader.add_warning(
            @provider.Warning::Deprecated(
              setting="providerOptions.metadata.user_id",
              message="Use 'providerOptions.metadata.userId'.",
            ),
          )
          Some(value)
        }
        Some(_) => {
          invalid_anthropic_option(
            reader, "metadata.userId", "Expected a string; metadata.userId was ignored.",
          )
          None
        }
        None => None
      }
  }
}

///|
fn parse_string_array(
  reader : @provider_utils.ProviderOptionsReader,
  field : String,
  aliases : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  guard reader.take_array(field, aliases~) is Some(values) else {
    return result
  }
  for value in values {
    match value {
      String(item) => result.push(item)
      _ =>
        invalid_anthropic_option(
          reader, field, "Expected an array of strings; invalid entries were ignored.",
        )
    }
  }
  result
}

///|
fn invalid_anthropic_nested_option(
  reader : @provider_utils.ProviderOptionsReader,
  field : String,
  expected : String,
) -> Unit {
  invalid_anthropic_option(
    reader,
    field,
    "Expected \{expected}; the invalid value was ignored.",
  )
}

///|
fn parse_anthropic_cache_control(
  reader : @provider_utils.ProviderOptionsReader,
) -> Json? {
  guard reader.take_object("cacheControl", aliases=["cache_control"])
    is Some(fields) else {
    return None
  }
  guard fields.get("type") == Some(Json::string("ephemeral")) else {
    invalid_anthropic_nested_option(
      reader, "cacheControl.type", "the literal string 'ephemeral'",
    )
    return None
  }
  let output : Map[String, Json] = Map([("type", Json::string("ephemeral"))])
  match fields.get("ttl") {
    Some(String(value)) if value == "5m" || value == "1h" =>
      output["ttl"] = Json::string(value)
    Some(_) => {
      invalid_anthropic_nested_option(
        reader, "cacheControl.ttl", "'5m' or '1h'",
      )
      return None
    }
    None => ()
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_mcp_tool_configuration(
  value : Json,
  reader : @provider_utils.ProviderOptionsReader,
  path : String,
) -> Json? {
  guard value is Object(fields) else {
    invalid_anthropic_nested_option(reader, path, "an object")
    return None
  }
  let output : Map[String, Json] = Map([])
  match anthropic_prompt_option(fields, "enabled", "enabled") {
    Some(True) => output["enabled"] = Json::boolean(true)
    Some(False) => output["enabled"] = Json::boolean(false)
    Some(Null) | None => ()
    Some(_) => {
      invalid_anthropic_nested_option(reader, path + ".enabled", "a boolean")
      return None
    }
  }
  match anthropic_prompt_option(fields, "allowedTools", "allowed_tools") {
    Some(Array(values)) => {
      let allowed : Array[Json] = []
      for item in values {
        match item {
          String(name) => allowed.push(Json::string(name))
          _ => {
            invalid_anthropic_nested_option(
              reader,
              path + ".allowedTools",
              "an array of strings",
            )
            return None
          }
        }
      }
      output["allowedTools"] = Json::array(allowed)
    }
    Some(Null) | None => ()
    Some(_) => {
      invalid_anthropic_nested_option(
        reader,
        path + ".allowedTools",
        "an array of strings",
      )
      return None
    }
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_mcp_server(
  value : Json,
  reader : @provider_utils.ProviderOptionsReader,
  index : Int,
) -> Json? {
  let path = "mcpServers[\{index}]"
  guard value is Object(fields) else {
    invalid_anthropic_nested_option(reader, path, "an object")
    return None
  }
  guard fields.get("type") == Some(Json::string("url")) else {
    invalid_anthropic_nested_option(
      reader,
      path + ".type",
      "the literal string 'url'",
    )
    return None
  }
  guard fields.get("name") is Some(String(name)) else {
    invalid_anthropic_nested_option(reader, path + ".name", "a string")
    return None
  }
  guard fields.get("url") is Some(String(url)) else {
    invalid_anthropic_nested_option(reader, path + ".url", "a string")
    return None
  }
  let output : Map[String, Json] = Map([
    ("type", Json::string("url")),
    ("name", Json::string(name)),
    ("url", Json::string(url)),
  ])
  match
    anthropic_prompt_option(fields, "authorizationToken", "authorization_token") {
    Some(String(value)) => output["authorizationToken"] = Json::string(value)
    Some(Null) | None => ()
    Some(_) => {
      invalid_anthropic_nested_option(
        reader,
        path + ".authorizationToken",
        "a string or null",
      )
      return None
    }
  }
  match
    anthropic_prompt_option(fields, "toolConfiguration", "tool_configuration") {
    Some(Null) | None => ()
    Some(value) =>
      match
        parse_anthropic_mcp_tool_configuration(
          value,
          reader,
          path + ".toolConfiguration",
        ) {
        Some(configuration) => output["toolConfiguration"] = configuration
        None => return None
      }
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_mcp_servers(
  reader : @provider_utils.ProviderOptionsReader,
) -> Array[Json] {
  guard reader.take_array("mcpServers", aliases=["mcp_servers"]) is Some(values) else {
    return []
  }
  let servers : Array[Json] = []
  for index, value in values {
    match parse_anthropic_mcp_server(value, reader, index) {
      Some(server) => servers.push(server)
      None => return []
    }
  }
  servers
}

///|
fn parse_anthropic_container_provider_reference(
  value : Json,
  reader : @provider_utils.ProviderOptionsReader,
  path : String,
) -> Json? {
  guard value is Object(fields) else {
    invalid_anthropic_nested_option(reader, path, "an object of string IDs")
    return None
  }
  let output : Map[String, Json] = Map([])
  for entry in fields.iter2() {
    let (provider_name, provider_id) = entry
    match provider_id {
      String(id) => output[provider_name] = Json::string(id)
      _ => {
        invalid_anthropic_nested_option(
          reader,
          path + "." + provider_name,
          "a string",
        )
        return None
      }
    }
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_container_skill_option(
  value : Json,
  reader : @provider_utils.ProviderOptionsReader,
  index : Int,
) -> Json? {
  let path = "container.skills[\{index}]"
  guard value is Object(fields) else {
    invalid_anthropic_nested_option(reader, path, "an object")
    return None
  }
  guard fields.get("type") is Some(String(kind)) &&
    (kind == "anthropic" || kind == "custom") else {
    invalid_anthropic_nested_option(
      reader,
      path + ".type",
      "'anthropic' or 'custom'",
    )
    return None
  }
  let output : Map[String, Json] = Map([("type", Json::string(kind))])
  if kind == "anthropic" {
    match anthropic_prompt_option(fields, "skillId", "skill_id") {
      Some(String(skill_id)) => output["skillId"] = Json::string(skill_id)
      _ => {
        invalid_anthropic_nested_option(reader, path + ".skillId", "a string")
        return None
      }
    }
  } else {
    guard anthropic_prompt_option(
        fields, "providerReference", "provider_reference",
      )
      is Some(reference) else {
      invalid_anthropic_nested_option(
        reader,
        path + ".providerReference",
        "an object of string IDs",
      )
      return None
    }
    match
      parse_anthropic_container_provider_reference(
        reference,
        reader,
        path + ".providerReference",
      ) {
      Some(value) => output["providerReference"] = value
      None => return None
    }
  }
  match fields.get("version") {
    Some(String(version)) => output["version"] = Json::string(version)
    Some(_) => {
      invalid_anthropic_nested_option(reader, path + ".version", "a string")
      return None
    }
    None => ()
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_container_option(
  reader : @provider_utils.ProviderOptionsReader,
) -> Json? {
  guard reader.take_object("container") is Some(fields) else { return None }
  let output : Map[String, Json] = Map([])
  match fields.get("id") {
    Some(String(id)) => output["id"] = Json::string(id)
    Some(_) => {
      invalid_anthropic_nested_option(reader, "container.id", "a string")
      return None
    }
    None => ()
  }
  match fields.get("skills") {
    Some(Array(values)) => {
      let skills : Array[Json] = []
      for index, value in values {
        match parse_anthropic_container_skill_option(value, reader, index) {
          Some(skill) => skills.push(skill)
          None => return None
        }
      }
      if skills.length() > 0 {
        output["skills"] = Json::array(skills)
      }
    }
    Some(_) => {
      invalid_anthropic_nested_option(reader, "container.skills", "an array")
      return None
    }
    None => ()
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_task_budget(
  reader : @provider_utils.ProviderOptionsReader,
) -> Json? {
  guard reader.take_object("taskBudget", aliases=["task_budget"])
    is Some(fields) else {
    return None
  }
  guard fields.get("type") == Some(Json::string("tokens")) else {
    invalid_anthropic_nested_option(
      reader, "taskBudget.type", "the literal string 'tokens'",
    )
    return None
  }
  let total = match fields.get("total") {
    Some(Number(value, ..)) =>
      match @provider_utils.json_number_as_int(value) {
        Some(total) if total >= 20000 => total
        _ => {
          invalid_anthropic_nested_option(
            reader, "taskBudget.total", "an integer greater than or equal to 20000",
          )
          return None
        }
      }
    _ => {
      invalid_anthropic_nested_option(
        reader, "taskBudget.total", "an integer greater than or equal to 20000",
      )
      return None
    }
  }
  let output : Map[String, Json] = Map([
    ("type", Json::string("tokens")),
    ("total", Json::number(total.to_double())),
  ])
  match fields.get("remaining") {
    Some(Number(value, ..)) =>
      match @provider_utils.json_number_as_int(value) {
        Some(remaining) if remaining >= 0 =>
          output["remaining"] = Json::number(remaining.to_double())
        _ => {
          invalid_anthropic_nested_option(
            reader, "taskBudget.remaining", "a non-negative integer",
          )
          return None
        }
      }
    Some(_) => {
      invalid_anthropic_nested_option(
        reader, "taskBudget.remaining", "a non-negative integer",
      )
      return None
    }
    None => ()
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_fallback(
  value : Json,
  reader : @provider_utils.ProviderOptionsReader,
  index : Int,
) -> Json? {
  let path = "fallbacks[\{index}]"
  guard value is Object(fields) else {
    invalid_anthropic_nested_option(reader, path, "an object")
    return None
  }
  guard fields.get("model") is Some(String(model)) else {
    invalid_anthropic_nested_option(reader, path + ".model", "a string")
    return None
  }
  let output : Map[String, Json] = Map([("model", Json::string(model))])
  match anthropic_prompt_option(fields, "maxTokens", "max_tokens") {
    Some(Number(value, ..)) =>
      match @provider_utils.json_number_as_int(value) {
        Some(max_tokens) =>
          output["max_tokens"] = Json::number(max_tokens.to_double())
        None => {
          invalid_anthropic_nested_option(
            reader,
            path + ".max_tokens",
            "an integer",
          )
          return None
        }
      }
    Some(_) => {
      invalid_anthropic_nested_option(
        reader,
        path + ".max_tokens",
        "an integer",
      )
      return None
    }
    None => ()
  }
  for names in [("thinking", "thinking"), ("outputConfig", "output_config")] {
    let (camel_name, wire_name) = names
    match anthropic_prompt_option(fields, camel_name, wire_name) {
      Some(Object(value)) => output[wire_name] = Json::object(value)
      Some(_) => {
        invalid_anthropic_nested_option(
          reader,
          path + "." + wire_name,
          "an object",
        )
        return None
      }
      None => ()
    }
  }
  match fields.get("speed") {
    Some(String(value)) if value == "fast" || value == "standard" =>
      output["speed"] = Json::string(value)
    Some(_) => {
      invalid_anthropic_nested_option(
        reader,
        path + ".speed",
        "'fast' or 'standard'",
      )
      return None
    }
    None => ()
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_fallbacks(
  reader : @provider_utils.ProviderOptionsReader,
) -> Json? {
  match reader.take_json("fallbacks") {
    Some(String("default")) => Some(Json::string("default"))
    Some(Array(values)) => {
      let fallbacks : Array[Json] = []
      for index, value in values {
        match parse_anthropic_fallback(value, reader, index) {
          Some(fallback) => fallbacks.push(fallback)
          None => return None
        }
      }
      Some(Json::array(fallbacks))
    }
    Some(_) => {
      invalid_anthropic_nested_option(
        reader, "fallbacks", "'default' or an array of fallback objects",
      )
      None
    }
    None => None
  }
}

///|
fn parse_anthropic_context_counter(
  value : Json,
  allowed_types : Array[String],
  reader : @provider_utils.ProviderOptionsReader,
  path : String,
) -> Json? {
  guard value is Object(fields) else {
    invalid_anthropic_nested_option(reader, path, "an object")
    return None
  }
  guard fields.get("type") is Some(String(kind)) && allowed_types.contains(kind) else {
    invalid_anthropic_nested_option(
      reader,
      path + ".type",
      "one of [\{allowed_types.join(", ")}]",
    )
    return None
  }
  guard fields.get("value") is Some(Number(number, ..)) else {
    invalid_anthropic_nested_option(reader, path + ".value", "a number")
    return None
  }
  Some({ "type": kind, "value": number })
}

///|
fn parse_anthropic_request_context_edit(
  value : Json,
  reader : @provider_utils.ProviderOptionsReader,
  index : Int,
) -> Json? {
  let path = "contextManagement.edits[\{index}]"
  guard value is Object(fields) else {
    invalid_anthropic_nested_option(reader, path, "an object")
    return None
  }
  guard fields.get("type") is Some(String(kind)) else {
    invalid_anthropic_nested_option(reader, path + ".type", "a string")
    return None
  }
  let output : Map[String, Json] = Map([("type", Json::string(kind))])
  match kind {
    "clear_tool_uses_20250919" => {
      match fields.get("trigger") {
        Some(trigger) =>
          match
            parse_anthropic_context_counter(
              trigger,
              ["input_tokens", "tool_uses"],
              reader,
              path + ".trigger",
            ) {
            Some(value) => output["trigger"] = value
            None => return None
          }
        None => ()
      }
      match fields.get("keep") {
        Some(keep) =>
          match
            parse_anthropic_context_counter(
              keep,
              ["tool_uses"],
              reader,
              path + ".keep",
            ) {
            Some(value) => output["keep"] = value
            None => return None
          }
        None => ()
      }
      match anthropic_prompt_option(fields, "clearAtLeast", "clear_at_least") {
        Some(clear_at_least) =>
          match
            parse_anthropic_context_counter(
              clear_at_least,
              ["input_tokens"],
              reader,
              path + ".clearAtLeast",
            ) {
            Some(value) => output["clearAtLeast"] = value
            None => return None
          }
        None => ()
      }
      match
        anthropic_prompt_option(fields, "clearToolInputs", "clear_tool_inputs") {
        Some(True) => output["clearToolInputs"] = Json::boolean(true)
        Some(False) => output["clearToolInputs"] = Json::boolean(false)
        Some(_) => {
          invalid_anthropic_nested_option(
            reader,
            path + ".clearToolInputs",
            "a boolean",
          )
          return None
        }
        None => ()
      }
      match anthropic_prompt_option(fields, "excludeTools", "exclude_tools") {
        Some(Array(values)) => {
          let tools : Array[Json] = []
          for item in values {
            match item {
              String(name) => tools.push(Json::string(name))
              _ => {
                invalid_anthropic_nested_option(
                  reader,
                  path + ".excludeTools",
                  "an array of strings",
                )
                return None
              }
            }
          }
          output["excludeTools"] = Json::array(tools)
        }
        Some(_) => {
          invalid_anthropic_nested_option(
            reader,
            path + ".excludeTools",
            "an array of strings",
          )
          return None
        }
        None => ()
      }
    }
    "clear_thinking_20251015" =>
      match fields.get("keep") {
        Some(String("all")) => output["keep"] = Json::string("all")
        Some(keep) =>
          match
            parse_anthropic_context_counter(
              keep,
              ["thinking_turns"],
              reader,
              path + ".keep",
            ) {
            Some(value) => output["keep"] = value
            None => return None
          }
        None => ()
      }
    "compact_20260112" => {
      match fields.get("trigger") {
        Some(trigger) =>
          match
            parse_anthropic_context_counter(
              trigger,
              ["input_tokens"],
              reader,
              path + ".trigger",
            ) {
            Some(value) => output["trigger"] = value
            None => return None
          }
        None => ()
      }
      match
        anthropic_prompt_option(
          fields, "pauseAfterCompaction", "pause_after_compaction",
        ) {
        Some(True) => output["pauseAfterCompaction"] = Json::boolean(true)
        Some(False) => output["pauseAfterCompaction"] = Json::boolean(false)
        Some(_) => {
          invalid_anthropic_nested_option(
            reader,
            path + ".pauseAfterCompaction",
            "a boolean",
          )
          return None
        }
        None => ()
      }
      match fields.get("instructions") {
        Some(String(value)) => output["instructions"] = Json::string(value)
        Some(_) => {
          invalid_anthropic_nested_option(
            reader,
            path + ".instructions",
            "a string",
          )
          return None
        }
        None => ()
      }
    }
    _ => {
      reader.add_warning(
        @provider.Warning::Other(
          message="Unknown context management strategy: \{kind}",
        ),
      )
      return None
    }
  }
  Some(Json::object(output))
}

///|
fn parse_anthropic_request_context_management(
  reader : @provider_utils.ProviderOptionsReader,
) -> Json? {
  guard reader.take_object("contextManagement", aliases=["context_management"])
    is Some(fields) else {
    return None
  }
  guard fields.get("edits") is Some(Array(values)) else {
    invalid_anthropic_nested_option(
      reader, "contextManagement.edits", "an array",
    )
    return None
  }
  let edits : Array[Json] = []
  for index, value in values {
    match parse_anthropic_request_context_edit(value, reader, index) {
      Some(edit) => edits.push(edit)
      None => return None
    }
  }
  Some({ "edits": edits })
}

///|
fn parse_anthropic_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> ParsedAnthropicOptions {
  let (resolution, used_custom_provider_key) = resolve_anthropic_options(
    provider_options, provider_name,
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let send_reasoning = reader
    .take_bool("sendReasoning", aliases=["send_reasoning"])
    .unwrap_or(true)
  let structured_output_mode = reader
    .take_string("structuredOutputMode", aliases=["structured_output_mode"], allowed=[
      "outputFormat", "jsonTool", "auto",
    ])
    .unwrap_or("auto")
  let thinking = parse_anthropic_thinking(reader)
  let disable_parallel_tool_use = reader.take_bool("disableParallelToolUse", aliases=[
    "disable_parallel_tool_use",
  ])
  let cache_control = parse_anthropic_cache_control(reader)
  let metadata_user_id = parse_metadata_user_id(reader)
  let mcp_servers = parse_anthropic_mcp_servers(reader)
  let container = parse_anthropic_container_option(reader)
  let tool_streaming = reader
    .take_bool("toolStreaming", aliases=["tool_streaming"])
    .unwrap_or(true)
  let effort = reader.take_string("effort", allowed=[
    "low", "medium", "high", "xhigh", "max",
  ])
  let task_budget = parse_anthropic_task_budget(reader)
  let speed = reader.take_string("speed", allowed=["fast", "standard"])
  let inference_geo = reader.take_string(
    "inferenceGeo",
    aliases=["inference_geo"],
    allowed=["us", "global"],
  )
  let fallbacks = parse_anthropic_fallbacks(reader)
  let beta_features = parse_string_array(reader, "anthropicBeta", [
    "anthropic_beta",
  ])
  let context_management = parse_anthropic_request_context_management(reader)
  {
    options: {
      send_reasoning,
      structured_output_mode,
      thinking,
      disable_parallel_tool_use,
      cache_control,
      metadata_user_id,
      mcp_servers,
      container,
      tool_streaming,
      effort,
      task_budget,
      speed,
      inference_geo,
      fallbacks,
      beta_features,
      context_management,
    },
    warnings: reader.diagnostics(),
    used_custom_provider_key,
  }
}

///|
fn map_anthropic_reasoning(
  effort : @provider.LanguageModelV4ReasoningEffort,
  capabilities : AnthropicModelCapabilities,
  warnings : Array[@provider.Warning],
) -> (AnthropicThinking?, String?) {
  match effort {
    @provider.V4ReasoningProviderDefault => (None, None)
    @provider.V4ReasoningNone => (Some(AnthropicThinkingDisabled), None)
    _ if capabilities.supports_adaptive_thinking => {
      let reasoning = effort.to_reasoning_effort()
      let effort_map : Map[String, String] = Map([
        ("minimal", "low"),
        ("low", "low"),
        ("medium", "medium"),
        ("high", "high"),
        (
          "xhigh",
          if capabilities.supports_xhigh_effort {
            "xhigh"
          } else {
            "max"
          },
        ),
      ])
      (
        Some(AnthropicThinkingAdaptive(Some(AnthropicThinkingSummarized))),
        @provider_utils.map_reasoning_to_provider_effort(
          reasoning, effort_map, warnings,
        ),
      )
    }
    _ => {
      let budget = @provider_utils.map_reasoning_to_provider_budget(
        effort.to_reasoning_effort(),
        capabilities.max_output_tokens,
        capabilities.max_output_tokens,
        warnings,
      )
      (
        match budget {
          Some(value) => Some(AnthropicThinkingEnabled(Some(value)))
          None => None
        },
        None,
      )
    }
  }
}

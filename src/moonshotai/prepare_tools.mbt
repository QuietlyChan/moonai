///|
priv struct MoonshotPreparedTools {
  tools : Array[Json]?
  tool_choice : Json?
  warnings : Array[@provider.Warning]
}

///|
/// Map V4 tools to Moonshot function tools with MFJS-normalized schemas.
///
/// Kimi K2.6 and the K2.7 Code models reject a required tool choice; the
/// setting is omitted with a warning for those models (AI SDK #19633).
fn prepare_moonshot_tools(
  tools~ : Array[@provider.LanguageModelV4Tool],
  tool_choice~ : @provider.LanguageModelV4ToolChoice?,
  model_id~ : String,
) -> MoonshotPreparedTools raise {
  let tool_warnings : Array[@provider.Warning] = []
  if tools.length() == 0 {
    return { tools: None, tool_choice: None, warnings: tool_warnings, }
  }
  let moonshot_tools : Array[Json] = []
  for tool in tools {
    match tool {
      @provider.V4ProviderTool(value) =>
        tool_warnings.push(
          @provider.Warning::Unsupported(
            feature="provider-defined tool \{value.id}",
            details="Moonshot AI accepts function tools only.",
          ),
        )
      @provider.V4FunctionTool(value) => {
        let function : Map[String, Json] = Map([
          ("name", Json::string(value.name)),
        ])
        if value.description is Some(description) {
          function["description"] = Json::string(description)
        }
        function["parameters"] = normalize_json_schema_for_mfjs(
          value.input_schema,
        )
        if value.strict is Some(strict) {
          function["strict"] = Json::boolean(strict)
        }
        moonshot_tools.push({
          "type": "function",
          "function": Json::object(function),
        })
      }
    }
  }
  let choice : Json? = match tool_choice {
    None => None
    Some(@provider.V4ToolChoiceAuto) => Some(Json::string("auto"))
    Some(@provider.V4ToolChoiceNone) => Some(Json::string("none"))
    Some(@provider.V4ToolChoiceRequired) =>
      if model_id == "kimi-k2.6" ||
        model_id == "kimi-k2.7-code" ||
        model_id == "kimi-k2.7-code-highspeed" {
        tool_warnings.push(
          @provider.Warning::Unsupported(
            feature="tool choice \"required\" for model \"\{model_id}\"",
            details="Moonshot AI rejects required tool choice for this model. The setting has been omitted; use \"auto\" or select a specific tool instead.",
          ),
        )
        None
      } else {
        Some(Json::string("required"))
      }
    Some(@provider.V4ToolChoiceTool(name)) => {
      let named : Json = { "type": "function", "function": { "name": name } }
      Some(named)
    }
  }
  { tools: Some(moonshot_tools), tool_choice: choice, warnings: tool_warnings, }
}

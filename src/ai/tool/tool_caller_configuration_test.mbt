///|
fn test_function_tool(description : String) -> @provider_utils.Tool {
  @provider_utils.Tool::function({ "type": "object" }, description~)
}

///|
test "local caller late-binds and hides local-only callees" {
  let local_caller = @provider_utils.experimental_tool_caller(
    test_function_tool("unbound"),
    @provider_utils.ToolCallerDefinition::local_caller(tools => {
      let names = [ for entry in tools.iter2() => Json::string(entry.0) ]
      @provider_utils.Tool::function(
        { "type": "object" },
        description=Json::array(names).stringify(),
      )
    }),
  )
  let tools = @provider_utils.tool_set([
    ("code_mode", local_caller),
    ("getInventory", test_function_tool("inventory")),
  ])
  let resolved = resolve_tool_caller_configuration(
    tools,
    Some(Map([("getInventory", [ToolCallerReference::tool("code_mode")])])),
  )
  let prepared = prepare_tools_for_tool_callers(tools, resolved)
  let model_tools = prepared.model_tools()
  assert_true(model_tools.get("code_mode") is Some(_))
  assert_true(model_tools.get("getInventory") is None)
  let bound = prepared.execution_tools().get("code_mode").unwrap()
  match bound.to_tool_definition("code_mode") {
    @provider.FunctionTool(description~, ..) =>
      assert_eq(description, Some("[\"getInventory\"]"))
    _ => fail("expected bound function tool")
  }
}

///|
test "provider caller prepares options and preserves direct access" {
  let provider_caller = @provider_utils.experimental_tool_caller(
    @provider_utils.Tool::provider(id="test.programmatic"),
    @provider_utils.ToolCallerDefinition::provider(options => {
      options["test"] = { "allowedCallers": ["programmatic"] }
      options
    }),
  )
  let tools = @provider_utils.tool_set([
    ("programmatic", provider_caller),
    ("getDemand", test_function_tool("demand")),
  ])
  let resolved = resolve_tool_caller_configuration(
    tools,
    Some(
      Map([
        (
          "getDemand",
          [
            ToolCallerReference::direct(),
            ToolCallerReference::tool("programmatic"),
          ],
        ),
      ]),
    ),
  )
  let prepared = prepare_tools_for_tool_callers(tools, resolved)
  let demand = prepared.model_tools().get("getDemand").unwrap()
  assert_eq(
    demand.provider_options().get("test"),
    Some({ "allowedCallers": ["programmatic"] }),
  )
}

///|
test "caller configuration rejects unknown tools and unregistered callers" {
  let tools = @provider_utils.tool_set([("plain", test_function_tool("plain"))])
  try
    resolve_tool_caller_configuration(
      tools,
      Some(Map([("missing", [ToolCallerReference::direct()])])),
    )
  catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "experimental_tool_callers")
      assert_true(message.contains("unknown tool"))
    }
  } noraise {
    _ => fail("expected unknown tool error")
  }
  try
    resolve_tool_caller_configuration(
      tools,
      Some(Map([("plain", [ToolCallerReference::tool("plain")])])),
    )
  catch {
    @provider.InvalidArgumentError(message~, ..) =>
      assert_true(message.contains("not registered"))
  } noraise {
    _ => fail("expected unregistered caller error")
  }
}

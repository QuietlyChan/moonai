///|
test "tool name mapping maps provider-defined tools in both directions" {
  let tools = [
    @provider.ToolDefinition::provider(
      id="anthropic.computer-use",
      name="custom-computer-tool",
    ),
    @provider.ToolDefinition::provider(
      id="openai.code-interpreter",
      name="custom-code-tool",
    ),
  ]
  let mapping = create_tool_name_mapping(
    tools,
    Map([
      ("anthropic.computer-use", "computer_use"),
      ("openai.code-interpreter", "code_interpreter"),
    ]),
  )
  assert_eq(
    mapping.to_provider_tool_name("custom-computer-tool"),
    "computer_use",
  )
  assert_eq(mapping.toProviderToolName("custom-code-tool"), "code_interpreter")
  assert_eq(mapping.to_custom_tool_name("computer_use"), "custom-computer-tool")
  assert_eq(mapping.toCustomToolName("code_interpreter"), "custom-code-tool")
}

///|
test "tool name mapping ignores function and unknown provider tools" {
  let mapping = createToolNameMapping(
    [
      @provider.ToolDefinition::new(
        "function-tool",
        ({ "type": "object" } : Json),
      ),
      @provider.ToolDefinition::provider(id="unknown.tool", name="custom-tool"),
    ],
    Map([("anthropic.computer-use", "computer_use")]),
  )
  assert_eq(mapping.toProviderToolName("function-tool"), "function-tool")
  assert_eq(mapping.toProviderToolName("custom-tool"), "custom-tool")
  assert_eq(mapping.toCustomToolName("unknown-name"), "unknown-name")
}

///|
test "empty tool name mapping is the identity" {
  let mapping = create_tool_name_mapping([], Map([]))
  assert_eq(mapping.to_provider_tool_name("any-tool"), "any-tool")
  assert_eq(mapping.to_custom_tool_name("any-tool"), "any-tool")
}

///|
test "tool name mapping matches AI SDK last-write collision behavior" {
  let mapping = create_tool_name_mapping(
    [
      @provider.ToolDefinition::provider(id="openai.first", name="first-custom"),
      @provider.ToolDefinition::provider(
        id="openai.second",
        name="second-custom",
      ),
    ],
    Map([("openai.first", "same"), ("openai.second", "same")]),
  )
  assert_eq(mapping.to_provider_tool_name("first-custom"), "same")
  assert_eq(mapping.to_provider_tool_name("second-custom"), "same")
  assert_eq(mapping.to_custom_tool_name("same"), "second-custom")
}

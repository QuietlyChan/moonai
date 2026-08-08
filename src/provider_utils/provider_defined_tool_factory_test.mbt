///|
async test "provider-defined tool factory forwards application-owned behavior" {
  let events : Array[String] = []
  let factory = create_provider_defined_tool_factory(id="test.shell", input_schema={
    "type": "object",
    "properties": { "command": { "type": "string" } },
    "required": ["command"],
  })
  let tool = factory.create(
    args={ "environment": "local" },
    output_schema={ "type": "object" },
    execute=(input, options) => {
      assert_eq(input, { "command": "pwd" })
      assert_eq(options.context, { "cwd": "/workspace" })
      { "stdout": "/workspace" }
    },
    needs_approval=ToolNeedsApproval::when((input, options) => {
      assert_eq(input, { "command": "pwd" })
      assert_eq(options.tool_call_id, "call-1")
      assert_eq(options.messages[0].content, "run pwd")
      assert_eq(options.context, { "cwd": "/workspace" })
      true
    }),
    to_model_output=options => {
      assert_eq(options.output, { "stdout": "/workspace" })
      ModelToolResultOutput::text("/workspace")
    },
    on_input_start=_options => events.push("start"),
    on_input_delta=options => events.push("delta:" + options.input_text_delta),
    on_input_available=_options => events.push("available"),
  )
  assert_true(!tool.is_provider_executed())
  assert_true(tool.is_executable())
  assert_eq(tool.output_schema(), Some({ "type": "object" }))
  match tool.to_tool_definition("shell") {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "test.shell")
      assert_eq(name, "shell")
      assert_eq(args, { "environment": "local" })
    }
    _ => fail("expected provider-defined transport tool")
  }
  let messages = [ModelMessage::user("run pwd")]
  let execution_options = ToolExecutionOptions::new(
    tool_call_id="call-1",
    messages~,
    context={ "cwd": "/workspace" },
  )
  assert_eq(
    tool.execute({ "command": "pwd" }, execution_options),
    Some({ "stdout": "/workspace" }),
  )
  assert_eq(
    tool.resolve_needs_approval(
      { "command": "pwd" },
      ToolNeedsApprovalOptions::new(tool_call_id="call-1", messages~, context={
        "cwd": "/workspace",
      }),
    ),
    Some(true),
  )
  assert_eq(
    tool.to_model_output(
      ToolModelOutputOptions::new(
        tool_call_id="call-1",
        input={ "command": "pwd" },
        output={ "stdout": "/workspace" },
      ),
    ),
    ModelToolResultOutput::text("/workspace"),
  )
  tool.invoke_input_start(execution_options)
  tool.invoke_input_delta(
    ToolInputDeltaOptions::new(input_text_delta="pwd", tool_call_id="call-1"),
  )
  tool.invoke_input_available(
    ToolInputAvailableOptions::new(
      input={ "command": "pwd" },
      tool_call_id="call-1",
    ),
  )
  assert_eq(events, ["start", "delta:pwd", "available"])
}

///|
test "provider-defined fixed-output factory owns its output schema" {
  let fixed_schema : Json = {
    "type": "object",
    "properties": { "text": { "type": "string" } },
  }
  let tool = createProviderDefinedToolFactoryWithOutputSchema(
    id="test.editor",
    input_schema={ "type": "object" },
    output_schema=fixed_schema,
  ).create(output_schema={ "type": "string" })
  assert_eq(tool.output_schema(), Some(fixed_schema))
  assert_true(!tool.is_provider_executed())
}

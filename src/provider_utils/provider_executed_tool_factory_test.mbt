///|
test "provider-executed tool factory attaches shared schemas and semantics" {
  let input_schema : Json = {
    "type": "object",
    "properties": { "query": { "type": "string" } },
    "required": ["query"],
  }
  let output_schema : Json = {
    "type": "object",
    "properties": { "answer": { "type": "string" } },
    "required": ["answer"],
  }
  let tool = create_provider_executed_tool_factory(
    id="test.search",
    input_schema~,
    output_schema~,
    supports_deferred_results=true,
  ).create(args={ "maxUses": 2 })
  assert_true(tool.is_provider_executed())
  assert_true(tool.supports_deferred_results())
  assert_eq(tool.input_schema(), Some(input_schema))
  assert_eq(tool.output_schema(), Some(output_schema))
  match tool.to_tool_definition("search") {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "test.search")
      assert_eq(name, "search")
      assert_eq(args, { "maxUses": 2 })
    }
    _ => fail("expected provider tool")
  }
}

///|
test "provider-executed tool factory defaults to immediate empty arguments" {
  let tool = createProviderExecutedToolFactory(
    id="test.clock",
    input_schema={ "type": "object" },
    output_schema={ "type": "string" },
  ).create()
  assert_true(tool.is_provider_executed())
  assert_true(!tool.supports_deferred_results())
  match tool.to_tool_definition("clock") {
    @provider.ProviderTool(args~, ..) => assert_eq(args, Json::empty_object())
    _ => fail("expected provider tool")
  }
}

///|
async test "provider-executed tool factory forwards input lifecycle callbacks" {
  let events : Array[String] = []
  let tool = create_provider_executed_tool_factory(
    id="test.search",
    input_schema={ "type": "object" },
    output_schema={ "type": "object" },
  ).create(
    on_input_start=_options => events.push("start"),
    on_input_delta=options => events.push("delta:" + options.input_text_delta),
    on_input_available=options => {
      events.push("available:" + options.input.stringify())
    },
  )
  tool.invoke_input_start(ToolExecutionOptions::new(tool_call_id="call-1"))
  tool.invoke_input_delta(
    ToolInputDeltaOptions::new(input_text_delta="{}", tool_call_id="call-1"),
  )
  tool.invoke_input_available(
    ToolInputAvailableOptions::new(
      input=Json::empty_object(),
      tool_call_id="call-1",
    ),
  )
  assert_eq(events, ["start", "delta:{}", "available:{}"])
}

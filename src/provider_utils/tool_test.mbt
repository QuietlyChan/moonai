///|
test "high-level function tool uses the ToolSet key as provider name" {
  let tool = Tool::function(
    { "type": "object" },
    description="lookup inventory",
    provider_options=Map([("test", { "enabled": true })]),
  )
  match tool.to_tool_definition("getInventory") {
    @provider.FunctionTool(name~, description~, provider_options~, ..) => {
      assert_eq(name, "getInventory")
      assert_eq(description, Some("lookup inventory"))
      assert_eq(provider_options.get("test"), Some({ "enabled": true }))
    }
    _ => fail("expected function tool")
  }
}

///|
test "function tool resolves a step-local description from context and sandbox" {
  let sandbox = SandboxSession::new(description="workspace sandbox", run=_ => {
    SandboxProcessResult::new(exit_code=0)
  })
  let original = Tool::function(
    { "type": "object" },
    description="fallback description",
    description_resolver=options => {
      let label = match options.context {
        { "label": String(value), .. } => value
        _ => "unknown"
      }
      "\{label} in \{options.experimental_sandbox.unwrap().description()}"
    },
  )
  let resolved = original.resolve_description(
    context={ "label": "lookup" },
    experimental_sandbox=sandbox,
  )
  match original.to_tool_definition("search") {
    @provider.FunctionTool(description~, ..) =>
      assert_eq(description, Some("fallback description"))
    _ => fail("expected original function tool")
  }
  match resolved.to_tool_definition("search") {
    @provider.FunctionTool(description~, ..) =>
      assert_eq(description, Some("lookup in workspace sandbox"))
    _ => fail("expected resolved function tool")
  }
}

///|
test "experimental provider tool caller prepares callee options" {
  let caller = experimental_tool_caller(
    Tool::provider(id="test.programmatic"),
    ToolCallerDefinition::provider(options => {
      options["test"] = { "allowedCallers": ["programmatic"] }
      options
    }),
  )
  let definition = experimental_get_tool_caller(caller).unwrap()
  assert_true(definition.is_provider())
  assert_eq(
    definition.prepare_provider_options(Map([])).get("test"),
    Some({ "allowedCallers": ["programmatic"] }),
  )
}

///|
async test "executable tool receives normalized execution options" {
  let tool = Tool::function({ "type": "object" }, execute=(input, options) => {
    "input": input,
    "toolCallId": options.tool_call_id,
  })
  assert_true(tool.is_executable())
  let output = tool.execute(
    { "sku": "sku-1" },
    ToolExecutionOptions::new(tool_call_id="call-1"),
  )
  assert_eq(
    output,
    Some({ "input": { "sku": "sku-1" }, "toolCallId": "call-1" }),
  )
}

///|
async test "tool input lifecycle callbacks receive copied normalized options" {
  let events : Array[Json] = []
  let token = @provider.CancellationToken::new()
  let messages = [ModelMessage::user("original input")]
  let tool = Tool::function(
    { "type": "object" },
    on_input_start=options => {
      events.push({
        "type": "start",
        "toolCallId": options.tool_call_id,
        "message": options.messages[0].content,
        "messageCount": options.messages.length(),
        "hasCancellation": options.cancellation_token is Some(_),
        "context": options.context,
      })
    },
    on_input_delta=options => {
      events.push({
        "type": "delta",
        "toolCallId": options.tool_call_id,
        "delta": options.input_text_delta,
        "message": options.messages[0].content,
        "messageCount": options.messages.length(),
        "hasCancellation": options.cancellation_token is Some(_),
        "context": options.context,
      })
    },
    on_input_available=options => {
      events.push({
        "type": "available",
        "toolCallId": options.tool_call_id,
        "input": options.input,
        "message": options.messages[0].content,
        "messageCount": options.messages.length(),
        "hasCancellation": options.cancellation_token is Some(_),
        "context": options.context,
      })
    },
  )
  let start_options = ToolExecutionOptions::new(
    tool_call_id="call-1",
    messages~,
    cancellation_token=token,
    context={ "requestId": "req-1" },
  )
  let delta_options = ToolInputDeltaOptions::new(
    input_text_delta="{\"value\":",
    tool_call_id="call-1",
    messages~,
    cancellation_token=token,
    context={ "requestId": "req-1" },
  )
  let available_options = ToolInputAvailableOptions::new(
    input={ "value": 1 },
    tool_call_id="call-1",
    messages~,
    cancellation_token=token,
    context={ "requestId": "req-1" },
  )
  messages.push(ModelMessage::user("later mutation"))
  tool.invoke_input_start(start_options)
  tool.invoke_input_delta(delta_options)
  tool.invoke_input_available(available_options)
  assert_eq(events, [
    {
      "type": "start",
      "toolCallId": "call-1",
      "message": "original input",
      "messageCount": 1,
      "hasCancellation": true,
      "context": { "requestId": "req-1" },
    },
    {
      "type": "delta",
      "toolCallId": "call-1",
      "delta": "{\"value\":",
      "message": "original input",
      "messageCount": 1,
      "hasCancellation": true,
      "context": { "requestId": "req-1" },
    },
    {
      "type": "available",
      "toolCallId": "call-1",
      "input": { "value": 1 },
      "message": "original input",
      "messageCount": 1,
      "hasCancellation": true,
      "context": { "requestId": "req-1" },
    },
  ])
}

///|
async test "tool model output uses AI SDK defaults and custom conversion" {
  let default_tool = Tool::function({ "type": "object" })
  assert_eq(
    default_tool.to_model_output(
      ToolModelOutputOptions::new(
        tool_call_id="call-text",
        input=Json::empty_object(),
        output="plain text",
      ),
    ),
    ModelToolResultOutput::text("plain text"),
  )
  assert_eq(
    default_tool.to_model_output(
      ToolModelOutputOptions::new(
        tool_call_id="call-json",
        input=Json::empty_object(),
        output={ "value": 1 },
      ),
    ),
    ModelToolResultOutput::json({ "value": 1 }),
  )
  let custom_tool = Tool::function({ "type": "object" }, to_model_output=options => {
    assert_eq(options.tool_call_id, "call-custom")
    assert_eq(options.input, { "query": "MoonBit" })
    assert_eq(options.output, { "matches": 1 })
    ModelToolResultOutput::content([
      ModelToolResultContentPart::text("one match"),
    ])
  })
  assert_eq(
    custom_tool.to_model_output(
      ToolModelOutputOptions::new(
        tool_call_id="call-custom",
        input={ "query": "MoonBit" },
        output={ "matches": 1 },
      ),
    ),
    ModelToolResultOutput::content([
      ModelToolResultContentPart::text("one match"),
    ]),
  )
}

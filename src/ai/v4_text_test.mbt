///|
async test "V4 high-level text generation uses the shared prompt layer" {
  let expected = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let mock = @testing.MockChatModel::new(
    [
      @provider.TextStart("text-0"),
      @provider.TextDelta(id="text-0", delta="hello"),
      @provider.TextEnd("text-0"),
    ],
    expected,
    provider_name="mock-v4",
    model_id="mock-chat",
  )
  let model = @model.as_language_model_v4(mock as &@provider.ChatModel)
  let result = generate_text(model, prompt="hello")
  assert_eq(result.finish_reason.unified, @provider.V4FinishStop)
  assert_eq(result.to_chat_response().text, "hello")
}

///|
async test "V4 high-level streaming preserves provider stream events" {
  let warning = @provider.Warning::unsupported("topK")
  let expected = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    @provider.Usage::new(input_tokens=2, output_tokens=1, total_tokens=3),
    @provider.Stop,
  ).with_diagnostics(None, None, { "mock-v4": { "trace_id": "trace-1" } }, [
    warning,
  ])
  let mock = @testing.MockChatModel::new(
    [
      @provider.StreamStart,
      @provider.Warning(warning),
      @provider.TextDelta(id="text-0", delta="hello"),
    ],
    expected,
    provider_name="mock-v4",
    model_id="mock-chat",
  )
  let model = @model.as_language_model_v4(mock as &@provider.ChatModel)
  let mut deltas = 0
  let mut starts = 0
  let mut finishes = 0
  let result = stream_text(model, prompt="hello", on_event=event => {
    match event {
      @provider.V4StreamStart(..) => starts = starts + 1
      @provider.V4TextDelta(..) => deltas = deltas + 1
      @provider.V4Finish(..) => finishes = finishes + 1
      _ => ()
    }
  })
  assert_eq(starts, 1)
  assert_eq(deltas, 1)
  assert_eq(finishes, 1)
  assert_eq(result.usage.input_tokens.total, Some(2))
  assert_eq(result.usage.output_tokens.total, Some(1))
  assert_eq(result.finish_reason.unified, @provider.V4FinishStop)
  assert_eq(result.warnings, [warning])
  assert_true(result.provider_metadata.get("mock-v4") is Some(_))
}

///|
async test "generate_text prepares caller-routed ToolSet before V4 model call" {
  let expected = @provider.ChatResponse::new(
    "done",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let mock = @testing.MockChatModel::new(
    [],
    expected,
    provider_name="mock-v4",
    model_id="mock-chat",
  )
  let captured_tools : Ref[Array[@provider.LanguageModelV4Tool]] = Ref([])
  let model = @model.wrap_language_model_v4(
    @model.as_language_model_v4(mock as &@provider.ChatModel),
    @provider.LanguageModelV4Middleware::new(transform_params=context => {
      captured_tools.val = context.params.tools.copy()
      context.params
    }),
  )
  let local_caller = @provider_utils.experimental_tool_caller(
    @provider_utils.Tool::function({ "type": "object" }),
    @provider_utils.ToolCallerDefinition::local_caller(_tools => {
      @provider_utils.Tool::function(
        { "type": "object" },
        description="bound local caller",
      )
    }),
  )
  let provider_caller = @provider_utils.experimental_tool_caller(
    @provider_utils.Tool::provider(id="test.programmatic"),
    @provider_utils.ToolCallerDefinition::provider(options => {
      options["test"] = { "allowedCallers": ["programmatic"] }
      options
    }),
  )
  let tools = @provider_utils.tool_set([
    ("code_mode", local_caller),
    ("programmatic", provider_caller),
    ("getInventory", @provider_utils.Tool::function({ "type": "object" })),
    ("getDemand", @provider_utils.Tool::function({ "type": "object" })),
  ])
  let _ = generate_text(
    model,
    prompt="route tools",
    tools~,
    experimental_tool_callers=Map([
      ("getInventory", [@tool.ToolCallerReference::tool("code_mode")]),
      (
        "getDemand",
        [
          @tool.ToolCallerReference::direct(),
          @tool.ToolCallerReference::tool("programmatic"),
        ],
      ),
    ]),
  )
  assert_false(captured_tools.val.any(tool => tool.name() == "getInventory"))
  assert_true(captured_tools.val.any(tool => tool.name() == "code_mode"))
  assert_true(
    captured_tools.val.any(tool => {
      match tool {
        @provider.V4FunctionTool(value) =>
          value.name == "getDemand" &&
          value.provider_options.get("test") ==
          Some({ "allowedCallers": ["programmatic"] })
        _ => false
      }
    }),
  )
}

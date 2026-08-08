///|
priv struct SequenceLanguageModel {
  results : Array[@provider.LanguageModelV4GenerateResult]
  call_count : Ref[Int]
  captured_options : Ref[Array[@provider.LanguageModelV4CallOptions]]
  provider_name : String
  model_name : String
}

///|
fn SequenceLanguageModel::new(
  results : Array[@provider.LanguageModelV4GenerateResult],
  provider_name? : String = "test.generate-text",
  model_name? : String = "sequence-model",
) -> SequenceLanguageModel {
  {
    results,
    call_count: Ref(0),
    captured_options: Ref([]),
    provider_name,
    model_name,
  }
}

///|
impl @provider.LanguageModelV4 for SequenceLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for SequenceLanguageModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.LanguageModelV4 for SequenceLanguageModel with fn model_id(self) -> String {
  self.model_name
}

///|
impl @provider.LanguageModelV4 for SequenceLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for SequenceLanguageModel with fn do_generate(
  self,
  options,
) {
  self.captured_options.val.push(options)
  let index = self.call_count.val
  self.call_count.val = index + 1
  guard index < self.results.length() else {
    fail("sequence language model received too many calls")
  }
  self.results[index]
}

///|
impl @provider.LanguageModelV4 for SequenceLanguageModel with fn do_stream(
  _self,
  _options,
  _on_event,
) {
  @provider.LanguageModelV4StreamResult::new(None, None)
}

///|
fn generation_result(
  content : Array[@provider.LanguageModelV4Content],
  input_tokens : Int,
  output_tokens : Int,
  finish_reason : @provider.LanguageModelV4UnifiedFinishReason,
) -> @provider.LanguageModelV4GenerateResult {
  {
    content,
    finish_reason: { unified: finish_reason, raw: None },
    usage: @provider.LanguageModelV4Usage::from_usage(
      @provider.Usage::new(input_tokens~, output_tokens~),
    ),
    provider_metadata: Map([]),
    request: None,
    response: None,
    warnings: [],
  }
}

///|
fn generated_tool_call(
  id : String,
  name : String,
  input : String,
  provider_executed? : Bool = false,
  dynamic? : Bool = false,
) -> @provider.LanguageModelV4Content {
  @provider.LanguageModelV4Content::tool_call({
    tool_call_id: id,
    tool_name: name,
    input,
    provider_executed,
    dynamic,
    provider_metadata: Map([]),
  })
}

///|
async test "generate_text invokes input callbacks for valid registered tools" {
  let callback_events : Array[Json] = []
  let token = @provider.CancellationToken::new()
  let sandbox = @provider_utils.SandboxSession::new(
    description="generate sandbox",
    run=_ => @provider_utils.SandboxProcessResult::new(exit_code=0),
  )
  let model = SequenceLanguageModel::new([
    generation_result(
      [
        generated_tool_call("call-valid", "weather", "{\"city\":\"Paris\"}"),
        generated_tool_call("call-invalid", "weather", "{}"),
        generated_tool_call(
          "call-dynamic",
          "provider_search",
          "{}",
          provider_executed=true,
          dynamic=true,
        ),
      ],
      1,
      2,
      @provider.V4FinishToolCalls,
    ),
  ])
  let weather = @provider_utils.Tool::function(
    {
      "type": "object",
      "properties": { "city": { "type": "string" } },
      "required": ["city"],
    },
    on_input_start=options => {
      callback_events.push({
        "type": "start",
        "toolCallId": options.tool_call_id,
        "message": options.messages[0].content,
        "context": options.context,
        "hasCancellation": options.cancellation_token is Some(_),
        "sandbox": options.experimental_sandbox.unwrap().description(),
      })
    },
    on_input_delta=_options => callback_events.push({ "type": "delta" }),
    on_input_available=options => {
      callback_events.push({
        "type": "available",
        "toolCallId": options.tool_call_id,
        "input": options.input,
        "message": options.messages[0].content,
        "context": options.context,
        "hasCancellation": options.cancellation_token is Some(_),
        "sandbox": options.experimental_sandbox.unwrap().description(),
      })
    },
  )
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    messages=[@provider_utils.ModelMessage::user("callback input")],
    tools=@provider_utils.tool_set([("weather", weather)]),
    runtime_context={ "requestId": "req-generate" },
    experimental_sandbox=sandbox,
    cancellation_token=token,
  )
  assert_eq(result.tool_calls.length(), 3)
  assert_eq(callback_events, [
    {
      "type": "start",
      "toolCallId": "call-valid",
      "message": "callback input",
      "context": { "requestId": "req-generate" },
      "hasCancellation": true,
      "sandbox": "generate sandbox",
    },
    {
      "type": "available",
      "toolCallId": "call-valid",
      "input": { "city": "Paris" },
      "message": "callback input",
      "context": { "requestId": "req-generate" },
      "hasCancellation": true,
      "sandbox": "generate sandbox",
    },
  ])
}

///|
async test "generate_text requests user approval before tool execution" {
  let executions = Ref(0)
  let approval_context : Array[Json] = []
  let model = SequenceLanguageModel::new([
    generation_result(
      [
        generated_tool_call(
          "call-approval", "shell", "{\"command\":\"rm draft\"}",
        ),
      ],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  let tools = @provider_utils.tool_set([
    (
      "shell",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "command": { "type": "string" } },
          "required": ["command"],
        },
        execute=(_input, _options) => {
          executions.val = executions.val + 1
          { "ok": true }
        },
        needs_approval=@provider_utils.ToolNeedsApproval::value(false),
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    messages=[@provider_utils.ModelMessage::user("remove the draft")],
    tools~,
    tool_approval=ToolApprovalConfiguration::generic(options => {
      approval_context.push({
        "toolName": options.tool_call.tool_name,
        "input": options.tool_call.input,
        "message": options.messages[0].content,
        "toolContext": options.tools_context["shell"],
        "runtimeContext": options.runtime_context,
        "hasTool": options.tools.get("shell") is Some(_),
      })
      ToolApprovalStatus::user_approval()
    }),
    tools_context=Map([("shell", { "cwd": "/workspace" })]),
    runtime_context={ "requestId": "req-approval" },
  )
  assert_eq(executions.val, 0)
  assert_eq(result.tool_results.length(), 0)
  assert_eq(result.tool_approval_requests.length(), 1)
  assert_eq(result.tool_approval_responses.length(), 0)
  assert_true(!result.tool_approval_requests[0].is_automatic)
  assert_eq(
    result.tool_approval_requests[0].tool_call.tool_call_id,
    "call-approval",
  )
  assert_eq(approval_context, [
    {
      "toolName": "shell",
      "input": { "command": "rm draft" },
      "message": "remove the draft",
      "toolContext": { "cwd": "/workspace" },
      "runtimeContext": { "requestId": "req-approval" },
      "hasTool": true,
    },
  ])
  assert_eq(result.response_messages.length(), 1)
  assert_true(
    result.response_messages[0].parts.any(part => {
      part.without_provider_options()
      is @provider_utils.ModelToolApprovalRequestPart(_)
    }),
  )
}

///|
async test "generate_text handles automatic approval and denial" {
  let executions : Array[String] = []
  let model = SequenceLanguageModel::new([
    generation_result(
      [
        generated_tool_call("call-approved", "approved", "{\"value\":1}"),
        generated_tool_call("call-denied", "denied", "{\"value\":2}"),
      ],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  let schema : Json = {
    "type": "object",
    "properties": { "value": { "type": "number" } },
    "required": ["value"],
  }
  let tools = @provider_utils.tool_set([
    (
      "approved",
      @provider_utils.Tool::function(
        schema,
        execute=(_input, _options) => {
          executions.push("approved")
          { "ok": true }
        },
        needs_approval=@provider_utils.ToolNeedsApproval::value(true),
      ),
    ),
    (
      "denied",
      @provider_utils.Tool::function(schema, execute=(_input, _options) => {
        executions.push("denied")
        { "ok": true }
      }),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="run both",
    tools~,
    tool_approval=ToolApprovalConfiguration::per_tool(
      Map([
        (
          "approved",
          ToolApprovalRule::status(
            ToolApprovalStatus::approved(reason="policy allows this call"),
          ),
        ),
        (
          "denied",
          ToolApprovalRule::status(
            ToolApprovalStatus::denied(reason="policy blocks this call"),
          ),
        ),
      ]),
    ),
  )
  assert_eq(executions, ["approved"])
  assert_eq(result.tool_results.length(), 1)
  assert_eq(result.tool_approval_requests.length(), 2)
  assert_eq(result.tool_approval_responses.length(), 2)
  assert_true(result.tool_approval_requests.all(value => value.is_automatic))
  assert_true(
    result.tool_approval_responses.any(value => {
      value.tool_call.tool_name == "approved" && value.approved
    }),
  )
  assert_true(
    result.tool_approval_responses.any(value => {
      value.tool_call.tool_name == "denied" &&
      !value.approved &&
      value.reason == Some("policy blocks this call")
    }),
  )
  assert_eq(result.response_messages.length(), 2)
  let tool_message = result.response_messages[1]
  assert_true(
    tool_message.parts.any(part => {
      part.without_provider_options()
      is @provider_utils.ModelToolApprovalResponsePart(response~) &&
      !response.approved &&
      response.reason == Some("policy blocks this call")
    }),
  )
  assert_true(
    tool_message.parts.any(part => {
      part.without_provider_options()
      is @provider_utils.ModelToolResultPart(result~) &&
      result.output is @provider_utils.ModelToolExecutionDenied(reason~, ..) &&
      reason == Some("policy blocks this call")
    }),
  )
}

///|
async test "generate_text executes a user-approved tool on the next call" {
  let executions = Ref(0)
  let tool = @provider_utils.Tool::function(
    {
      "type": "object",
      "properties": { "command": { "type": "string" } },
      "required": ["command"],
    },
    execute=(input, _options) => {
      executions.val = executions.val + 1
      assert_eq(input, { "command": "publish" })
      { "published": true }
    },
    needs_approval=@provider_utils.ToolNeedsApproval::value(true),
  )
  let tools = @provider_utils.tool_set([("release", tool)])
  let first_model = SequenceLanguageModel::new([
    generation_result(
      [
        generated_tool_call(
          "call-release", "release", "{\"command\":\"publish\"}",
        ),
      ],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  let user_message = @provider_utils.ModelMessage::user("publish the release")
  let first = generate_text(
    first_model as &@provider.LanguageModelV4,
    messages=[user_message],
    tools~,
  )
  assert_eq(executions.val, 0)
  let request = first.tool_approval_requests[0]
  let history = [user_message]
  for message in first.response_messages {
    history.push(message.copy())
  }
  history.push(
    @provider_utils.ModelMessage::tool_content([
      @provider_utils.ModelContentPart::tool_approval_response(
        @provider_utils.ModelToolApprovalResponse::new(
          approval_id=request.approval_id,
          approved=true,
          reason="approved by user",
        ),
      ),
    ]),
  )
  let second_model = SequenceLanguageModel::new([
    generation_result(
      [@provider.LanguageModelV4Content::text("published")],
      2,
      1,
      @provider.V4FinishStop,
    ),
  ])
  let second = generate_text(
    second_model as &@provider.LanguageModelV4,
    messages=history,
    tools~,
  )
  assert_eq(executions.val, 1)
  assert_eq(second.text(), "published")
  let prompt_messages = second_model.captured_options.val[0].prompt.messages
  assert_eq(prompt_messages.length(), 3)
  match prompt_messages[2] {
    @provider.V4ToolMessage(content=[@provider.V4PromptToolResult(result)], ..) =>
      assert_true(
        result.output
        is @provider.V4ToolResultJsonOutput(value={ "published": true, .. }, ..),
      )
    _ => fail("expected approved tool output before the next model call")
  }
}

///|
async test "generate_text defaults to one completed step" {
  let executions = Ref(0)
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-1", "weather", "{\"city\":\"Paris\"}")],
      1,
      2,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [@provider.LanguageModelV4Content::text("unused")],
      3,
      4,
      @provider.V4FinishStop,
    ),
  ])
  let tools = @provider_utils.tool_set([
    (
      "weather",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        execute=(_input, _options) => {
          executions.val = executions.val + 1
          { "temperature": 18 }
        },
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="weather",
    tools~,
  )
  assert_eq(model.call_count.val, 1)
  assert_eq(executions.val, 1)
  assert_eq(result.steps.length(), 1)
  assert_eq(result.tool_results.length(), 1)
}

///|
async test "generate_text executes tools and appends response messages across steps" {
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-1", "weather", "{\"city\":\"Paris\"}")],
      1,
      2,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [@provider.LanguageModelV4Content::text("It is 18 C.")],
      3,
      4,
      @provider.V4FinishStop,
    ),
  ])
  let tools = @provider_utils.tool_set([
    (
      "weather",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        execute=(_input, _options) => { "temperature": 18 },
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="weather",
    tools~,
    stop_when=[is_step_count(2)],
  )
  assert_eq(model.call_count.val, 2)
  assert_eq(result.steps.length(), 2)
  assert_eq(result.text(), "It is 18 C.")
  assert_eq(result.usage.input_tokens.total, Some(4))
  assert_eq(result.usage.output_tokens.total, Some(6))
  assert_eq(result.response_messages.length(), 3)
  let second_prompt = model.captured_options.val[1].prompt.messages
  assert_eq(second_prompt.length(), 3)
  assert_true(second_prompt[1] is @provider.V4AssistantMessage(..))
  assert_true(second_prompt[2] is @provider.V4ToolMessage(..))
}

///|
async test "generate_text sends custom tool model output while retaining raw output" {
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-1", "weather", "{\"city\":\"Paris\"}")],
      1,
      2,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [@provider.LanguageModelV4Content::text("done")],
      3,
      4,
      @provider.V4FinishStop,
    ),
  ])
  let tools = @provider_utils.tool_set([
    (
      "weather",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        execute=(_input, _options) => { "temperature": 18 },
        to_model_output=options => {
          assert_eq(options.tool_call_id, "call-1")
          assert_eq(options.input, { "city": "Paris" })
          assert_eq(options.output, { "temperature": 18 })
          @provider_utils.ModelToolResultOutput::text("converted weather")
        },
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="weather",
    tools~,
    stop_when=[is_step_count(2)],
  )
  assert_eq(result.tool_results[0].output, { "temperature": 18 })
  let second_prompt = model.captured_options.val[1].prompt.messages
  match second_prompt[2] {
    @provider.V4ToolMessage(
      content=[@provider.V4PromptToolResult(tool_result)],
      ..
    ) =>
      assert_true(
        tool_result.output
        is @provider.V4ToolResultTextOutput(value="converted weather", ..),
      )
    _ => fail("expected converted text tool result in the second prompt")
  }
}

///|
async test "invalid tool input becomes a tool error without executing" {
  let executions = Ref(0)
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-invalid", "weather", "{\"cities\":[]}")],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  let tools = @provider_utils.tool_set([
    (
      "weather",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        execute=(_input, _options) => {
          executions.val = executions.val + 1
          Json::null()
        },
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="weather",
    tools~,
  )
  assert_eq(executions.val, 0)
  assert_true(result.tool_calls[0].invalid)
  assert_true(result.tool_calls[0].dynamic)
  assert_true(result.tool_results[0].is_error)
  assert_eq(result.steps[0].response_messages.length(), 2)
}

///|
async test "tool execution failures become error results" {
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-failed", "unstable", "{}")],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="run tool",
    tools=@provider_utils.tool_set([
      (
        "unstable",
        @provider_utils.Tool::function({ "type": "object" }, execute=(
          _input,
          _options,
        ) => fail("tool execution failed")),
      ),
    ]),
  )
  assert_eq(result.tool_results.length(), 1)
  assert_true(result.tool_results[0].is_error)
  assert_true(
    @debug.to_string(result.tool_results[0].output).contains(
      "tool execution failed",
    ),
  )
  assert_eq(result.steps[0].response_messages.length(), 2)
}

///|
async test "tool execution cancellation is never converted to a tool error" {
  let token = @provider.CancellationToken::new()
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-cancelled", "cancel", "{}")],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  try
    generate_text(
      model as &@provider.LanguageModelV4,
      prompt="cancel tool",
      tools=@provider_utils.tool_set([
        (
          "cancel",
          @provider_utils.Tool::function({ "type": "object" }, execute=(
            _input,
            _options,
          ) => {
            token.cancel()
            @provider.check_cancellation(Some(token))
            Json::null()
          }),
        ),
      ]),
      cancellation_token=token,
    )
  catch {
    @provider.CancellationError => ()
    error => fail("unexpected cancellation error: \{error}")
  } noraise {
    _ => fail("expected tool cancellation to propagate")
  }
}

///|
async test "tool without execute callback stops the natural loop" {
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-1", "weather", "{}")],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [@provider.LanguageModelV4Content::text("unused")],
      1,
      1,
      @provider.V4FinishStop,
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="weather",
    tools=@provider_utils.tool_set([
      ("weather", @provider_utils.Tool::function({ "type": "object" })),
    ]),
    stop_when=[is_step_count(3)],
  )
  assert_eq(model.call_count.val, 1)
  assert_eq(result.steps.length(), 1)
  assert_eq(result.tool_results.length(), 0)
}

///|
async test "deferred provider tool result keeps the loop active until resolved" {
  let model = SequenceLanguageModel::new([
    generation_result(
      [
        generated_tool_call(
          "server-call-1",
          "code_execution",
          "{}",
          provider_executed=true,
        ),
      ],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [
        @provider.LanguageModelV4Content::tool_result({
          tool_call_id: "server-call-1",
          tool_name: "code_execution",
          result: { "stdout": "done" },
          is_error: false,
          preliminary: false,
          dynamic: false,
          provider_metadata: Map([]),
        }),
        @provider.LanguageModelV4Content::text("done"),
      ],
      2,
      2,
      @provider.V4FinishStop,
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="run code",
    tools=@provider_utils.tool_set([
      (
        "code_execution",
        @provider_utils.Tool::provider(
          id="anthropic.code_execution_20260120",
          supports_deferred_results=true,
        ),
      ),
    ]),
    stop_when=[is_step_count(3)],
  )
  assert_eq(model.call_count.val, 2)
  assert_eq(result.steps.length(), 2)
  assert_eq(result.text(), "done")
  assert_eq(result.tool_results.length(), 1)
  assert_true(result.tool_results[0].provider_executed)
}

///|
async test "OpenAI programmatic caller prepares and executes callee tools across steps" {
  let executions = Ref(0)
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("lookup-1", "lookup", "{\"query\":\"MoonBit\"}")],
      2,
      1,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [@provider.LanguageModelV4Content::text("MoonBit found")],
      3,
      2,
      @provider.V4FinishStop,
    ),
  ])
  let tools = @provider_utils.tool_set([
    (
      "programmatic",
      @openai.create_openai(api_key="test-key")
      .tools()
      .programmaticToolCalling(),
    ),
    (
      "lookup",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "query": { "type": "string" } },
          "required": ["query"],
        },
        execute=(_input, _options) => {
          executions.val = executions.val + 1
          { "matches": 1 }
        },
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="search",
    tools~,
    experimental_tool_callers=Map([
      ("lookup", [@tool.ToolCallerReference::tool("programmatic")]),
    ]),
    stop_when=[is_step_count(2)],
  )
  assert_eq(executions.val, 1)
  assert_eq(result.steps.length(), 2)
  assert_eq(result.text(), "MoonBit found")
  let first_step_tools = model.captured_options.val[0].tools
  assert_true(
    first_step_tools.any(tool => {
      match tool {
        @provider.V4ProviderTool(value) =>
          value.id == "openai.programmatic_tool_calling"
        _ => false
      }
    }),
  )
  assert_true(
    first_step_tools.any(tool => {
      match tool {
        @provider.V4FunctionTool(value) =>
          value.name == "lookup" &&
          value.provider_options.get("openai") ==
          Some({ "allowedCallers": ["programmatic"] })
        _ => false
      }
    }),
  )
}

///|
async test "Anthropic code execution caller keeps deferred provider work in the loop" {
  let executions = Ref(0)
  let model = SequenceLanguageModel::new([
    generation_result(
      [
        generated_tool_call(
          "code-1",
          "code_execution",
          "{\"code\":\"lookup()\"}",
          provider_executed=true,
        ),
        generated_tool_call("lookup-1", "lookup", "{\"query\":\"MoonBit\"}"),
      ],
      2,
      1,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [
        @provider.LanguageModelV4Content::tool_result({
          tool_call_id: "code-1",
          tool_name: "code_execution",
          result: { "stdout": "1 result" },
          is_error: false,
          preliminary: false,
          dynamic: false,
          provider_metadata: Map([]),
        }),
        @provider.LanguageModelV4Content::text("MoonBit found"),
      ],
      3,
      2,
      @provider.V4FinishStop,
    ),
  ])
  let tools = @provider_utils.tool_set([
    ("code_execution", @anthropic.code_execution_20260120()),
    (
      "lookup",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "query": { "type": "string" } },
          "required": ["query"],
        },
        execute=(_input, _options) => {
          executions.val = executions.val + 1
          { "matches": 1 }
        },
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="search with code",
    tools~,
    experimental_tool_callers=Map([
      ("lookup", [@tool.ToolCallerReference::tool("code_execution")]),
    ]),
    stop_when=[is_step_count(3)],
  )
  assert_eq(executions.val, 1)
  assert_eq(result.steps.length(), 2)
  assert_eq(result.text(), "MoonBit found")
  assert_true(result.tool_results.any(value => value.provider_executed))
  let first_step_tools = model.captured_options.val[0].tools
  assert_true(
    first_step_tools.any(tool => {
      match tool {
        @provider.V4ProviderTool(value) =>
          value.id == "anthropic.code_execution_20260120"
        _ => false
      }
    }),
  )
  assert_true(
    first_step_tools.any(tool => {
      match tool {
        @provider.V4FunctionTool(value) =>
          value.name == "lookup" &&
          value.provider_options.get("anthropic") ==
          Some({ "allowedCallers": ["code_execution_20260120"] })
        _ => false
      }
    }),
  )
}

///|
async test "prepare_step carries state while model call overrides stay local" {
  let observed_tool_context = Ref(Json::null())
  let primary = SequenceLanguageModel::new(
    [
      generation_result(
        [generated_tool_call("lookup-1", "lookup", "{\"query\":\"MoonBit\"}")],
        2,
        1,
        @provider.V4FinishToolCalls,
      ),
    ],
    provider_name="test.primary",
    model_name="primary-model",
  )
  let alternate = SequenceLanguageModel::new(
    [
      generation_result(
        [@provider.LanguageModelV4Content::text("prepared answer")],
        3,
        2,
        @provider.V4FinishStop,
      ),
    ],
    provider_name="test.alternate",
    model_name="alternate-model",
  )
  let tools = @provider_utils.tool_set([
    (
      "lookup",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "query": { "type": "string" } },
          "required": ["query"],
        },
        execute=(_input, options) => {
          observed_tool_context.val = options.context
          { "matches": 1 }
        },
      ),
    ),
  ])
  let result = generate_text(
    primary as &@provider.LanguageModelV4,
    messages=[@provider_utils.ModelMessage::user("original prompt")],
    instructions=@prompt.Instructions::text("outer instructions"),
    tools~,
    stop_when=[is_step_count(3)],
    max_output_tokens=100,
    temperature=1.0,
    stop_sequences=["outer"],
    reasoning_effort=@provider.High,
    provider_options=Map([("test", { "outer": true })]),
    runtime_context={ "phase": "outer" },
    tools_context=Map([("lookup", { "label": "outer" })]),
    prepare_step=options => {
      assert_eq(options.model.model_id(), "primary-model")
      assert_eq(options.initial_messages.length(), 1)
      assert_true(
        options.initial_instructions
        is Some(@prompt.InstructionText("outer instructions")),
      )
      if options.step_number == 0 {
        assert_eq(options.steps.length(), 0)
        assert_eq(options.response_messages.length(), 0)
        assert_eq(options.messages[0].content, "original prompt")
        Some(
          PrepareStepResult::new(
            instructions=@prompt.Instructions::text("prepared instructions"),
            messages=[@provider_utils.ModelMessage::user("prepared prompt")],
            runtime_context={ "phase": "prepared" },
            tools_context=Map([("lookup", { "label": "prepared" })]),
            provider_options=Map([("test", { "step": 1 })]),
            max_output_tokens=50,
            temperature=0.0,
            stop_sequences=[],
            reasoning_effort=@provider.ProviderDefault,
          ),
        )
      } else {
        assert_eq(options.step_number, 1)
        assert_eq(options.steps.length(), 1)
        assert_eq(options.response_messages.length(), 2)
        assert_eq(options.messages.length(), 3)
        assert_eq(options.messages[0].content, "prepared prompt")
        assert_true(
          options.instructions
          is Some(@prompt.InstructionText("prepared instructions")),
        )
        assert_eq(options.runtime_context, { "phase": "prepared" })
        assert_eq(
          options.tools_context.get("lookup"),
          Some({ "label": "prepared" }),
        )
        Some(
          PrepareStepResult::new(model=alternate as &@provider.LanguageModelV4),
        )
      }
    },
  )
  assert_eq(primary.call_count.val, 1)
  assert_eq(alternate.call_count.val, 1)
  assert_eq(result.steps.length(), 2)
  assert_eq(result.steps[0].model_id, "primary-model")
  assert_eq(result.steps[1].model_id, "alternate-model")
  assert_eq(result.steps[1].runtime_context, { "phase": "prepared" })
  assert_eq(
    result.steps[1].tools_context.get("lookup"),
    Some({ "label": "prepared" }),
  )
  assert_eq(observed_tool_context.val, { "label": "prepared" })
  let first_options = primary.captured_options.val[0]
  assert_eq(first_options.max_output_tokens, Some(50))
  assert_eq(first_options.temperature, Some(0.0))
  assert_eq(first_options.stop_sequences, [])
  assert_eq(first_options.reasoning, @provider.V4ReasoningProviderDefault)
  assert_eq(
    first_options.provider_options.get("test"),
    Some({ "outer": true, "step": 1 }),
  )
  let second_options = alternate.captured_options.val[0]
  assert_eq(second_options.max_output_tokens, Some(100))
  assert_eq(second_options.temperature, Some(1.0))
  assert_eq(second_options.stop_sequences, ["outer"])
  assert_eq(second_options.reasoning, @provider.V4ReasoningHigh)
  assert_eq(
    second_options.provider_options.get("test"),
    Some({ "outer": true }),
  )
  assert_eq(result.text(), "prepared answer")
}

///|
async test "prepare_step sandbox override is local to one generate_text step" {
  let outer_sandbox = @provider_utils.SandboxSession::new(
    description="outer sandbox",
    run=_ => @provider_utils.SandboxProcessResult::new(exit_code=0),
  )
  let step_sandbox = @provider_utils.SandboxSession::new(
    description="step sandbox",
    run=_ => @provider_utils.SandboxProcessResult::new(exit_code=0),
  )
  let observed_prepare_sandboxes : Array[String] = []
  let observed_execution_sandboxes : Array[String] = []
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("lookup-1", "lookup", "{\"query\":\"one\"}")],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [generated_tool_call("lookup-2", "lookup", "{\"query\":\"two\"}")],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
    generation_result(
      [@provider.LanguageModelV4Content::text("done")],
      1,
      1,
      @provider.V4FinishStop,
    ),
  ])
  let tools = @provider_utils.tool_set([
    (
      "lookup",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "query": { "type": "string" } },
          "required": ["query"],
        },
        description_resolver=options => {
          let label = match options.context {
            { "label": String(value), .. } => value
            _ => "unknown"
          }
          "\{label} in \{options.experimental_sandbox.unwrap().description()}"
        },
        execute=(_input, options) => {
          let description = options.experimental_sandbox.unwrap().description()
          observed_execution_sandboxes.push(description)
          { "sandbox": description }
        },
      ),
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    prompt="lookup twice",
    tools~,
    tools_context=Map([("lookup", { "label": "outer" })]),
    experimental_sandbox=outer_sandbox,
    stop_when=[is_step_count(4)],
    prepare_step=options => {
      observed_prepare_sandboxes.push(
        options.experimental_sandbox.unwrap().description(),
      )
      if options.step_number == 0 {
        Some(
          PrepareStepResult::new(
            tools_context=Map([("lookup", { "label": "step" })]),
            experimental_sandbox=step_sandbox,
          ),
        )
      } else {
        None
      }
    },
  )
  assert_eq(result.steps.length(), 3)
  assert_eq(observed_prepare_sandboxes, [
    "outer sandbox", "outer sandbox", "outer sandbox",
  ])
  assert_eq(observed_execution_sandboxes, ["step sandbox", "outer sandbox"])
  let descriptions : Array[String] = []
  for call_options in model.captured_options.val {
    match call_options.tools[0] {
      @provider.V4FunctionTool(value) =>
        descriptions.push(
          value.description.unwrap_or("missing dynamic lookup description"),
        )
      _ => fail("expected a dynamically described lookup tool")
    }
  }
  assert_eq(descriptions, [
    "step in step sandbox", "step in outer sandbox", "step in outer sandbox",
  ])
}

///|
async test "active_tools and tool_order are resolved before provider calls" {
  let model = SequenceLanguageModel::new([
    generation_result(
      [@provider.LanguageModelV4Content::text("done")],
      1,
      1,
      @provider.V4FinishStop,
    ),
  ])
  let schema : Json = { "type": "object" }
  let tools = @provider_utils.tool_set([
    ("zebra", @provider_utils.Tool::function(schema)),
    ("alpha", @provider_utils.Tool::function(schema)),
    ("middle", @provider_utils.Tool::function(schema)),
  ])
  ignore(
    generate_text(
      model as &@provider.LanguageModelV4,
      prompt="order tools",
      tools~,
      active_tools=["middle"],
      tool_order=["middle"],
      prepare_step=_ => {
        Some(
          PrepareStepResult::new(active_tools=["zebra", "alpha"], tool_order=[
            "alpha",
          ]),
        )
      },
    ),
  )
  let names : Array[String] = []
  for tool in model.captured_options.val[0].tools {
    match tool {
      @provider.V4FunctionTool(value) => names.push(value.name)
      @provider.V4ProviderTool(_) => ()
    }
  }
  assert_eq(names, ["alpha", "zebra"])
}

///|
async test "prepare_step validates per-step model call settings" {
  let model = SequenceLanguageModel::new([
    generation_result(
      [@provider.LanguageModelV4Content::text("unused")],
      1,
      1,
      @provider.V4FinishStop,
    ),
  ])
  try
    generate_text(
      model as &@provider.LanguageModelV4,
      prompt="validate settings",
      prepare_step=_ => Some(PrepareStepResult::new(max_output_tokens=0)),
    )
  catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "max_output_tokens")
      assert_true(message.contains("greater than or equal to 1"))
    }
    error => fail("unexpected prepare_step error: \{error}")
  } noraise {
    _ => fail("invalid prepare_step settings must fail")
  }
  assert_eq(model.call_count.val, 0)
}

///|
async test "generate_text signs and validates tool approval replay" {
  let executions = Ref(0)
  let secret = ToolApprovalSecret::string("approval-replay-secret")
  let tools = @provider_utils.tool_set([
    (
      "release",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "command": { "type": "string" } },
          "required": ["command"],
        },
        execute=(input, _options) => {
          executions.val = executions.val + 1
          assert_eq(input, { "command": "publish" })
          { "published": true }
        },
        needs_approval=@provider_utils.ToolNeedsApproval::value(true),
      ),
    ),
  ])
  let first_model = SequenceLanguageModel::new([
    generation_result(
      [
        generated_tool_call(
          "call-signed", "release", "{\"command\":\"publish\"}",
        ),
      ],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  let user_message = @provider_utils.ModelMessage::user("publish the release")
  let first = generate_text(
    first_model as &@provider.LanguageModelV4,
    messages=[user_message],
    tools~,
    experimental_tool_approval_secret=secret,
  )
  let request = first.tool_approval_requests[0]
  assert_true(request.signature is Some(_))
  assert_true(
    first.response_messages[0].parts.any(part => {
      part.without_provider_options()
      is @provider_utils.ModelToolApprovalRequestPart(request=history_request) &&
      history_request.signature == request.signature
    }),
  )
  let history = [user_message]
  for message in first.response_messages {
    history.push(message.copy())
  }
  history.push(
    @provider_utils.ModelMessage::tool_content([
      @provider_utils.ModelContentPart::tool_approval_response(
        @provider_utils.ModelToolApprovalResponse::new(
          approval_id=request.approval_id,
          approved=true,
        ),
      ),
    ]),
  )
  let second_model = SequenceLanguageModel::new([
    generation_result(
      [@provider.LanguageModelV4Content::text("published")],
      2,
      1,
      @provider.V4FinishStop,
    ),
  ])
  let second = generate_text(
    second_model as &@provider.LanguageModelV4,
    messages=history,
    tools~,
    experimental_tool_approval_secret=secret,
  )
  assert_eq(executions.val, 1)
  assert_eq(second.text(), "published")
}

///|
async test "generate_text rejects unsigned approval replay when signing is configured" {
  let executions = Ref(0)
  let tools = @provider_utils.tool_set([
    (
      "release",
      @provider_utils.Tool::function(
        { "type": "object" },
        execute=(_input, _options) => {
          executions.val = executions.val + 1
          { "published": true }
        },
        needs_approval=@provider_utils.ToolNeedsApproval::value(true),
      ),
    ),
  ])
  let expected_approval_id = "approval-unsigned"
  let history = [
    @provider_utils.ModelMessage::user("publish"),
    @provider_utils.ModelMessage::assistant_parts([
      @provider_utils.ModelContentPart::tool_call(
        @provider_utils.ModelToolCall::new(
          id="call-unsigned",
          name="release",
          input=Json::empty_object(),
        ),
      ),
      @provider_utils.ModelContentPart::tool_approval_request(
        @provider_utils.ModelToolApprovalRequest::new(
          approval_id=expected_approval_id,
          tool_call_id="call-unsigned",
        ),
      ),
    ]),
    @provider_utils.ModelMessage::tool_content([
      @provider_utils.ModelContentPart::tool_approval_response(
        @provider_utils.ModelToolApprovalResponse::new(
          approval_id=expected_approval_id,
          approved=true,
        ),
      ),
    ]),
  ]
  let model = SequenceLanguageModel::new([
    generation_result(
      [@provider.LanguageModelV4Content::text("must not run")],
      1,
      1,
      @provider.V4FinishStop,
    ),
  ])
  try
    generate_text(
      model as &@provider.LanguageModelV4,
      messages=history,
      tools~,
      experimental_tool_approval_secret=ToolApprovalSecret::string(
        "required-secret",
      ),
    )
  catch {
    @generate_text.InvalidToolApprovalSignatureError(
      approval_id~,
      tool_call_id~,
      reason~
    ) => {
      assert_eq(approval_id, expected_approval_id)
      assert_eq(tool_call_id, "call-unsigned")
      assert_eq(reason, "missing signature")
    }
    error => fail("unexpected approval signature error: \{error}")
  } noraise {
    _ => fail("unsigned approval replay must fail")
  }
  assert_eq(executions.val, 0)
  assert_eq(model.call_count.val, 0)
}

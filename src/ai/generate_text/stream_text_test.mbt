///|
priv struct SequenceStreamLanguageModel {
  streams : Array[Array[@provider.LanguageModelV4StreamPart]]
  call_count : Ref[Int]
  captured_options : Ref[Array[@provider.LanguageModelV4CallOptions]]
  provider_name : String
  model_name : String
}

///|
fn SequenceStreamLanguageModel::new(
  streams : Array[Array[@provider.LanguageModelV4StreamPart]],
  provider_name? : String = "test.stream-text",
  model_name? : String = "sequence-stream-model",
) -> SequenceStreamLanguageModel {
  {
    streams,
    call_count: Ref(0),
    captured_options: Ref([]),
    provider_name,
    model_name,
  }
}

///|
impl @provider.LanguageModelV4 for SequenceStreamLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for SequenceStreamLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
impl @provider.LanguageModelV4 for SequenceStreamLanguageModel with fn model_id(
  self,
) -> String {
  self.model_name
}

///|
impl @provider.LanguageModelV4 for SequenceStreamLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for SequenceStreamLanguageModel with fn do_generate(
  _self,
  _options,
) {
  fail("sequence stream model does not support generate")
}

///|
impl @provider.LanguageModelV4 for SequenceStreamLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  self.captured_options.val.push(options)
  let index = self.call_count.val
  self.call_count.val = index + 1
  guard index < self.streams.length() else {
    fail("sequence stream model received too many calls")
  }
  for event in self.streams[index] {
    on_event(event)
  }
  @provider.LanguageModelV4StreamResult::new(None, None)
}

///|
fn stream_usage(
  input_tokens : Int,
  output_tokens : Int,
) -> @provider.LanguageModelV4Usage {
  @provider.LanguageModelV4Usage::from_usage(
    @provider.Usage::new(input_tokens~, output_tokens~),
  )
}

///|
fn stream_finish(
  input_tokens : Int,
  output_tokens : Int,
  reason : @provider.LanguageModelV4UnifiedFinishReason,
) -> @provider.LanguageModelV4StreamPart {
  @provider.V4Finish(
    usage=stream_usage(input_tokens, output_tokens),
    reason={ unified: reason, raw: None },
    provider_metadata=Map([]),
  )
}

///|
fn stream_tool_call(
  id : String,
  name : String,
  input : String,
  provider_executed? : Bool = false,
) -> @provider.LanguageModelV4StreamPart {
  @provider.V4ToolCallReady({
    tool_call_id: id,
    tool_name: name,
    input,
    provider_executed,
    dynamic: false,
    provider_metadata: Map([]),
  })
}

///|
async test "stream_text invokes input callbacks after matching stream events" {
  let order : Array[String] = []
  let callback_payloads : Array[Json] = []
  let token = @provider.CancellationToken::new()
  let sandbox = @provider_utils.SandboxSession::new(
    description="stream sandbox",
    run=_ => @provider_utils.SandboxProcessResult::new(exit_code=0),
  )
  let model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      @provider.V4ToolInputStart(
        id="call-1",
        tool_name="lookup",
        provider_executed=false,
        dynamic=false,
        title=None,
        provider_metadata=Map([]),
      ),
      @provider.V4ToolInputDelta(
        id="call-1",
        delta="{\"query\":\"Moon",
        provider_metadata=Map([]),
      ),
      @provider.V4ToolInputDelta(
        id="call-1",
        delta="Bit\"}",
        provider_metadata=Map([]),
      ),
      @provider.V4ToolInputEnd(id="call-1", provider_metadata=Map([])),
      stream_tool_call("call-1", "lookup", "{\"query\":\"MoonBit\"}"),
      stream_finish(1, 2, @provider.V4FinishToolCalls),
    ],
  ])
  let lookup = @provider_utils.Tool::function(
    {
      "type": "object",
      "properties": { "query": { "type": "string" } },
      "required": ["query"],
    },
    on_input_start=options => {
      order.push("callback:start")
      callback_payloads.push({
        "type": "start",
        "toolCallId": options.tool_call_id,
        "message": options.messages[0].content,
        "context": options.context,
        "hasCancellation": options.cancellation_token is Some(_),
        "sandbox": options.experimental_sandbox.unwrap().description(),
      })
    },
    on_input_delta=options => {
      order.push("callback:delta:" + options.input_text_delta)
      callback_payloads.push({
        "type": "delta",
        "toolCallId": options.tool_call_id,
        "delta": options.input_text_delta,
        "message": options.messages[0].content,
        "context": options.context,
        "hasCancellation": options.cancellation_token is Some(_),
        "sandbox": options.experimental_sandbox.unwrap().description(),
      })
    },
    on_input_available=options => {
      order.push("callback:available")
      callback_payloads.push({
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
  let result = stream_text(
    model as &@provider.LanguageModelV4,
    messages=[@provider_utils.ModelMessage::user("stream callback input")],
    tools=@provider_utils.tool_set([("lookup", lookup)]),
    runtime_context={ "requestId": "req-stream" },
    experimental_sandbox=sandbox,
    cancellation_token=token,
    on_event=event => {
      match event {
        @provider.V4ToolInputStart(..) => order.push("event:start")
        @provider.V4ToolInputDelta(delta~, ..) =>
          order.push("event:delta:" + delta)
        @provider.V4ToolInputEnd(..) => order.push("event:end")
        @provider.V4ToolCallReady(_) => order.push("event:ready")
        _ => ()
      }
    },
  )
  assert_eq(result.tool_calls.length(), 1)
  assert_eq(order, [
    "event:start", "callback:start", "event:delta:{\"query\":\"Moon", "callback:delta:{\"query\":\"Moon",
    "event:delta:Bit\"}", "callback:delta:Bit\"}", "event:end", "event:ready", "callback:available",
  ])
  assert_eq(callback_payloads, [
    {
      "type": "start",
      "toolCallId": "call-1",
      "message": "stream callback input",
      "context": { "requestId": "req-stream" },
      "hasCancellation": true,
      "sandbox": "stream sandbox",
    },
    {
      "type": "delta",
      "toolCallId": "call-1",
      "delta": "{\"query\":\"Moon",
      "message": "stream callback input",
      "context": { "requestId": "req-stream" },
      "hasCancellation": true,
      "sandbox": "stream sandbox",
    },
    {
      "type": "delta",
      "toolCallId": "call-1",
      "delta": "Bit\"}",
      "message": "stream callback input",
      "context": { "requestId": "req-stream" },
      "hasCancellation": true,
      "sandbox": "stream sandbox",
    },
    {
      "type": "available",
      "toolCallId": "call-1",
      "input": { "query": "MoonBit" },
      "message": "stream callback input",
      "context": { "requestId": "req-stream" },
      "hasCancellation": true,
      "sandbox": "stream sandbox",
    },
  ])
}

///|
async test "stream_text sends custom tool model output on the next step" {
  let model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      stream_tool_call("call-1", "lookup", "{\"query\":\"MoonBit\"}"),
      stream_finish(1, 2, @provider.V4FinishToolCalls),
    ],
    [
      @provider.V4StreamStart(warnings=[]),
      @provider.V4TextStart(id="text-1", provider_metadata=Map([])),
      @provider.V4TextDelta(
        id="text-1",
        delta="done",
        provider_metadata=Map([]),
      ),
      @provider.V4TextEnd(id="text-1", provider_metadata=Map([])),
      stream_finish(3, 4, @provider.V4FinishStop),
    ],
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
        execute=(_input, _options) => { "matches": 1 },
        to_model_output=options => {
          assert_eq(options.input, { "query": "MoonBit" })
          assert_eq(options.output, { "matches": 1 })
          @provider_utils.ModelToolResultOutput::text("converted lookup")
        },
      ),
    ),
  ])
  let result = stream_text(
    model as &@provider.LanguageModelV4,
    prompt="lookup",
    tools~,
    stop_when=[is_step_count(2)],
  )
  assert_eq(result.tool_results[0].output, { "matches": 1 })
  let second_prompt = model.captured_options.val[1].prompt.messages
  match second_prompt[2] {
    @provider.V4ToolMessage(
      content=[@provider.V4PromptToolResult(tool_result)],
      ..
    ) =>
      assert_true(
        tool_result.output
        is @provider.V4ToolResultTextOutput(value="converted lookup", ..),
      )
    _ => fail("expected converted text tool result in the second prompt")
  }
}

///|
async test "stream_text executes OpenAI programmatic caller tools across steps" {
  let executions = Ref(0)
  let observed_starts = Ref(0)
  let observed_finishes = Ref(0)
  let model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      stream_tool_call("lookup-1", "lookup", "{\"query\":\"MoonBit\"}"),
      stream_finish(2, 1, @provider.V4FinishToolCalls),
    ],
    [
      @provider.V4StreamStart(warnings=[]),
      @provider.V4TextStart(id="text-1", provider_metadata=Map([])),
      @provider.V4TextDelta(
        id="text-1",
        delta="MoonBit found",
        provider_metadata=Map([]),
      ),
      @provider.V4TextEnd(id="text-1", provider_metadata=Map([])),
      stream_finish(3, 2, @provider.V4FinishStop),
    ],
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
  let result = stream_text(
    model as &@provider.LanguageModelV4,
    prompt="search",
    tools~,
    experimental_tool_callers=Map([
      ("lookup", [@tool.ToolCallerReference::tool("programmatic")]),
    ]),
    stop_when=[is_step_count(2)],
    on_event=event => {
      match event {
        @provider.V4StreamStart(..) =>
          observed_starts.val = observed_starts.val + 1
        @provider.V4Finish(..) =>
          observed_finishes.val = observed_finishes.val + 1
        _ => ()
      }
    },
  )
  assert_eq(model.call_count.val, 2)
  assert_eq(executions.val, 1)
  assert_eq(observed_starts.val, 2)
  assert_eq(observed_finishes.val, 2)
  assert_eq(result.steps.length(), 2)
  assert_eq(result.text(), "MoonBit found")
  assert_eq(result.usage.input_tokens.total, Some(5))
  assert_eq(result.usage.output_tokens.total, Some(3))
  assert_eq(result.usage.raw, None)
  assert_eq(result.tool_calls.length(), 1)
  assert_eq(result.tool_results.length(), 1)
  assert_eq(result.response_messages.length(), 3)
  let second_prompt = model.captured_options.val[1].prompt.messages
  assert_eq(second_prompt.length(), 3)
  assert_true(second_prompt[1] is @provider.V4AssistantMessage(..))
  assert_true(second_prompt[2] is @provider.V4ToolMessage(..))
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
async test "stream_text waits for Anthropic deferred caller results" {
  let executions = Ref(0)
  let model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      stream_tool_call(
        "code-1",
        "code_execution",
        "{\"code\":\"lookup()\"}",
        provider_executed=true,
      ),
      stream_tool_call("lookup-1", "lookup", "{\"query\":\"MoonBit\"}"),
      stream_finish(2, 1, @provider.V4FinishToolCalls),
    ],
    [
      @provider.V4StreamStart(warnings=[]),
      @provider.V4ToolResultReady({
        tool_call_id: "code-1",
        tool_name: "code_execution",
        result: { "stdout": "1 result" },
        is_error: false,
        preliminary: false,
        dynamic: false,
        provider_metadata: Map([]),
      }),
      @provider.V4TextStart(id="text-2", provider_metadata=Map([])),
      @provider.V4TextDelta(
        id="text-2",
        delta="MoonBit found",
        provider_metadata=Map([]),
      ),
      @provider.V4TextEnd(id="text-2", provider_metadata=Map([])),
      stream_finish(3, 2, @provider.V4FinishStop),
    ],
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
  let result = stream_text(
    model as &@provider.LanguageModelV4,
    prompt="search with code",
    tools~,
    experimental_tool_callers=Map([
      ("lookup", [@tool.ToolCallerReference::tool("code_execution")]),
    ]),
    stop_when=[is_step_count(3)],
  )
  assert_eq(model.call_count.val, 2)
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
async test "stream_text shares prepare_step state and model switching" {
  let observed_tool_context = Ref(Json::null())
  let observed_tool_sandbox = Ref("")
  let outer_sandbox = @provider_utils.SandboxSession::new(
    description="outer stream sandbox",
    run=_ => @provider_utils.SandboxProcessResult::new(exit_code=0),
  )
  let step_sandbox = @provider_utils.SandboxSession::new(
    description="step stream sandbox",
    run=_ => @provider_utils.SandboxProcessResult::new(exit_code=0),
  )
  let primary = SequenceStreamLanguageModel::new(
    [
      [
        @provider.V4StreamStart(warnings=[]),
        stream_tool_call("lookup-1", "lookup", "{\"query\":\"MoonBit\"}"),
        stream_finish(2, 1, @provider.V4FinishToolCalls),
      ],
    ],
    provider_name="test.stream-primary",
    model_name="stream-primary-model",
  )
  let alternate = SequenceStreamLanguageModel::new(
    [
      [
        @provider.V4StreamStart(warnings=[]),
        @provider.V4TextStart(id="text-2", provider_metadata=Map([])),
        @provider.V4TextDelta(
          id="text-2",
          delta="streamed answer",
          provider_metadata=Map([]),
        ),
        @provider.V4TextEnd(id="text-2", provider_metadata=Map([])),
        stream_finish(3, 2, @provider.V4FinishStop),
      ],
    ],
    provider_name="test.stream-alternate",
    model_name="stream-alternate-model",
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
          observed_tool_sandbox.val = options.experimental_sandbox
            .unwrap()
            .description()
          { "matches": 1 }
        },
      ),
    ),
  ])
  let result = stream_text(
    primary as &@provider.LanguageModelV4,
    prompt="original prompt",
    tools~,
    stop_when=[is_step_count(3)],
    max_output_tokens=100,
    temperature=1.0,
    runtime_context={ "phase": "outer" },
    tools_context=Map([("lookup", { "label": "outer" })]),
    experimental_sandbox=outer_sandbox,
    prepare_step=options => {
      assert_eq(
        options.experimental_sandbox.unwrap().description(),
        "outer stream sandbox",
      )
      if options.step_number == 0 {
        Some(
          PrepareStepResult::new(
            messages=[@provider_utils.ModelMessage::user("prepared prompt")],
            runtime_context={ "phase": "prepared" },
            tools_context=Map([("lookup", { "label": "prepared" })]),
            experimental_sandbox=step_sandbox,
            max_output_tokens=50,
            temperature=0.0,
          ),
        )
      } else {
        assert_eq(options.steps.length(), 1)
        assert_eq(options.response_messages.length(), 2)
        assert_eq(options.messages.length(), 3)
        assert_eq(options.messages[0].content, "prepared prompt")
        assert_eq(options.runtime_context, { "phase": "prepared" })
        Some(
          PrepareStepResult::new(model=alternate as &@provider.LanguageModelV4),
        )
      }
    },
  )
  assert_eq(primary.call_count.val, 1)
  assert_eq(alternate.call_count.val, 1)
  assert_eq(primary.captured_options.val[0].max_output_tokens, Some(50))
  assert_eq(primary.captured_options.val[0].temperature, Some(0.0))
  assert_eq(alternate.captured_options.val[0].max_output_tokens, Some(100))
  assert_eq(alternate.captured_options.val[0].temperature, Some(1.0))
  assert_eq(observed_tool_context.val, { "label": "prepared" })
  assert_eq(observed_tool_sandbox.val, "step stream sandbox")
  assert_eq(result.steps[0].model_id, "stream-primary-model")
  assert_eq(result.steps[1].model_id, "stream-alternate-model")
  assert_eq(result.steps[1].runtime_context, { "phase": "prepared" })
  assert_eq(result.text(), "streamed answer")
}

///|
async test "stream_text requests user approval before tool execution" {
  let executions = Ref(0)
  let approval_context : Array[Json] = []
  let model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      stream_tool_call("call-approval", "shell", "{\"command\":\"rm draft\"}"),
      stream_finish(1, 1, @provider.V4FinishToolCalls),
    ],
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
  let result = stream_text(
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
    runtime_context={ "requestId": "req-stream-approval" },
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
      "runtimeContext": { "requestId": "req-stream-approval" },
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
async test "stream_text handles automatic approval and denial" {
  let executions : Array[String] = []
  let model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      stream_tool_call("call-approved", "approved", "{\"value\":1}"),
      stream_tool_call(
        "call-denied",
        "denied",
        "{\"value\":2}",
        provider_executed=true,
      ),
      stream_finish(1, 1, @provider.V4FinishToolCalls),
    ],
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
  let result = stream_text(
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
  let denied_approval_id = result.tool_approval_responses[1].approval_id
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
      reason == Some("policy blocks this call") &&
      result.provider_options["openai"] == { "approvalId": denied_approval_id }
    }),
  )
}

///|
async test "stream_text executes a user-approved tool before streaming" {
  let executions = Ref(0)
  let secret = ToolApprovalSecret::bytes(b"stream-approval-secret")
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
  let first_model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      stream_tool_call("call-release", "release", "{\"command\":\"publish\"}"),
      stream_finish(1, 1, @provider.V4FinishToolCalls),
    ],
  ])
  let user_message = @provider_utils.ModelMessage::user("publish the release")
  let first = stream_text(
    first_model as &@provider.LanguageModelV4,
    messages=[user_message],
    tools~,
    experimental_tool_approval_secret=secret,
  )
  assert_eq(executions.val, 0)
  let request = first.tool_approval_requests[0]
  assert_true(request.signature is Some(_))
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
  let second_model = SequenceStreamLanguageModel::new([
    [
      @provider.V4StreamStart(warnings=[]),
      @provider.V4TextStart(id="text-approved", provider_metadata=Map([])),
      @provider.V4TextDelta(
        id="text-approved",
        delta="published",
        provider_metadata=Map([]),
      ),
      @provider.V4TextEnd(id="text-approved", provider_metadata=Map([])),
      stream_finish(2, 1, @provider.V4FinishStop),
    ],
  ])
  let execution_counts_at_events : Array[Int] = []
  let second = stream_text(
    second_model as &@provider.LanguageModelV4,
    messages=history,
    tools~,
    experimental_tool_approval_secret=secret,
    on_event=_event => execution_counts_at_events.push(executions.val),
  )
  assert_eq(executions.val, 1)
  assert_true(execution_counts_at_events.all(count => count == 1))
  assert_eq(second.text(), "published")
  let prompt_messages = second_model.captured_options.val[0].prompt.messages
  assert_eq(prompt_messages.length(), 3)
  match prompt_messages[2] {
    @provider.V4ToolMessage(content=[@provider.V4PromptToolResult(result)], ..) =>
      assert_true(
        result.output
        is @provider.V4ToolResultJsonOutput(value={ "published": true, .. }, ..),
      )
    _ => fail("expected approved tool output before the first stream event")
  }
}

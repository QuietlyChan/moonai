///|
priv struct AgentSequenceModel {
  results : Array[@provider.LanguageModelV4GenerateResult]
  stream_steps : Array[Array[@provider.LanguageModelV4StreamPart]]
  call_count : Ref[Int]
  captured_headers : Ref[Array[Map[String, String]]]
  captured_temperatures : Ref[Array[Double?]]
}

///|
fn AgentSequenceModel::new(
  results : Array[@provider.LanguageModelV4GenerateResult],
  stream_steps? : Array[Array[@provider.LanguageModelV4StreamPart]] = [],
) -> AgentSequenceModel {
  {
    results,
    stream_steps,
    call_count: Ref(0),
    captured_headers: Ref([]),
    captured_temperatures: Ref([]),
  }
}

///|
impl @provider.LanguageModelV4 for AgentSequenceModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for AgentSequenceModel with fn provider(_self) -> String {
  "test.agent"
}

///|
impl @provider.LanguageModelV4 for AgentSequenceModel with fn model_id(_self) -> String {
  "agent-loop-model"
}

///|
impl @provider.LanguageModelV4 for AgentSequenceModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for AgentSequenceModel with fn do_generate(
  self,
  options,
) {
  self.captured_headers.val.push(@provider_utils.copy_headers(options.headers))
  let index = self.call_count.val
  self.call_count.val = index + 1
  guard index < self.results.length() else {
    fail("agent sequence model received too many generate calls")
  }
  self.results[index]
}

///|
impl @provider.LanguageModelV4 for AgentSequenceModel with fn do_stream(
  self,
  options,
  on_event,
) {
  self.captured_headers.val.push(@provider_utils.copy_headers(options.headers))
  self.captured_temperatures.val.push(options.temperature)
  let index = self.call_count.val
  self.call_count.val = index + 1
  guard index < self.stream_steps.length() else {
    fail("agent sequence model received too many stream calls")
  }
  for event in self.stream_steps[index] {
    on_event(event)
  }
  @provider.LanguageModelV4StreamResult::new(None, None)
}

///|
fn agent_model_tool_call(
  id : String,
  name : String,
  input : String,
) -> @provider.LanguageModelV4Content {
  @provider.LanguageModelV4Content::tool_call({
    tool_call_id: id,
    tool_name: name,
    input,
    provider_executed: false,
    dynamic: false,
    provider_metadata: Map([]),
  })
}

///|
fn agent_finish(
  reason : @provider.LanguageModelV4UnifiedFinishReason,
) -> @provider.LanguageModelV4StreamPart {
  @provider.V4Finish(
    usage=@provider.LanguageModelV4Usage::from_usage(
      @provider.Usage::new(input_tokens=1, output_tokens=1),
    ),
    reason={ unified: reason, raw: None, },
    provider_metadata=Map([]),
  )
}

///|
fn agent_loop_tools(executions : Ref[Int]) -> @provider_utils.ToolSet {
  @provider_utils.tool_set([
    (
      "lookup",
      @provider_utils.Tool::function(
        {
          "type": "object",
          "properties": { "query": { "type": "string" } },
          "required": ["query"],
        },
        execute=(input, _options) => {
          executions.val = executions.val + 1
          match input {
            { "query": String(query), .. } => { "answer": query }
            _ => { "answer": Json::null() }
          }
        },
        to_model_output=options => {
          @provider_utils.ModelToolResultOutput::text(
            options.output.stringify(),
          )
        },
      ),
    ),
  ])
}

///|
fn agent_text_stream_step(
  text~ : String,
) -> Array[@provider.LanguageModelV4StreamPart] {
  [
    @provider.V4StreamStart(warnings=[]),
    @provider.V4TextStart(id="txt-0", provider_metadata=Map([])),
    @provider.V4TextDelta(id="txt-0", delta=text, provider_metadata=Map([])),
    @provider.V4TextEnd(id="txt-0", provider_metadata=Map([])),
    agent_finish(@provider.V4FinishStop),
  ]
}

///|
fn agent_generate_step(
  content : Array[@provider.LanguageModelV4Content],
  reason : @provider.LanguageModelV4UnifiedFinishReason,
) -> @provider.LanguageModelV4GenerateResult {
  {
    content,
    finish_reason: { unified: reason, raw: None, },
    usage: @provider.LanguageModelV4Usage::from_usage(
      @provider.Usage::new(input_tokens=1, output_tokens=1),
    ),
    warnings: [],
    provider_metadata: Map([]),
    request: None,
    response: None,
  }
}

///|
async test "ToolLoopAgent runs the tool loop and tags the agent header" {
  let executions : Ref[Int] = Ref(0)
  let model = AgentSequenceModel::new([
    agent_generate_step(
      [agent_model_tool_call("call-1", "lookup", "{\"query\":\"Moon\"}")],
      @provider.V4FinishToolCalls,
    ),
    agent_generate_step(
      [@provider.LanguageModelV4Content::text("Moon it is")],
      @provider.V4FinishStop,
    ),
  ])
  let agent = ToolLoopAgent::new(
    settings=ToolLoopAgentSettings::new(
      model=model as &@provider.LanguageModelV4,
      id="research-agent",
      tools=agent_loop_tools(executions),
      runtime_context={ "requestId": "req-agent-1" },
    ),
  )
  assert_eq(agent.version(), AGENT_VERSION)
  assert_eq(agent.id(), Some("research-agent"))
  assert_true(agent.tools().get("lookup") is Some(_))
  let dynamic : &Agent = agent
  let result = dynamic.generate(AgentCallOptions::new(prompt="what is Moon?"))
  assert_eq(result.text(), "Moon it is")
  assert_eq(result.tool_results.length(), 1)
  assert_eq(executions.val, 1)
  // Outgoing requests carry the agent attribution suffix.
  assert_eq(model.captured_headers.val.length(), 2)
  for headers in model.captured_headers.val {
    match headers.get("User-Agent") {
      Some(value) => assert_true(value.contains("ai-sdk-agent/tool-loop"))
      None =>
        match headers.get("user-agent") {
          Some(value) => assert_true(value.contains("ai-sdk-agent/tool-loop"))
          None => fail("expected a user-agent header on agent requests")
        }
    }
  }
}

///|
async test "ToolLoopAgent streams a single step" {
  let executions : Ref[Int] = Ref(0)
  let model = AgentSequenceModel::new([], stream_steps=[
    agent_text_stream_step(text="streamed answer"),
  ])
  let agent = ToolLoopAgent::new(
    settings=ToolLoopAgentSettings::new(
      model=model as &@provider.LanguageModelV4,
      tools=agent_loop_tools(executions),
      runtime_context={ "requestId": "settings-level" },
    ),
  )
  let dynamic : &Agent = agent
  let result = dynamic.stream(
    AgentCallOptions::new(prompt="tell me", runtime_context={
      "requestId": "call-level",
    }),
  )
  assert_eq(result.text(), "streamed answer")
  assert_eq(model.call_count.val, 1)
  assert_eq(executions.val, 0)
}

///|
async test "ToolLoopAgent prepare_call hook rewrites the merged call" {
  let model = AgentSequenceModel::new([], stream_steps=[
    agent_text_stream_step(text="hooked"),
  ])
  let seen_prompts : Array[String?] = []
  let agent = ToolLoopAgent::new(
    settings=ToolLoopAgentSettings::new(
      model=model as &@provider.LanguageModelV4,
      prepare_call=Some(draft => {
        seen_prompts.push(draft.call.prompt)
        {
          settings: { ..draft.settings, temperature: Some(0.5), },
          call: draft.call,
        }
      }),
    ),
  )
  let dynamic : &Agent = agent
  let result = dynamic.stream(AgentCallOptions::new(prompt="hello"))
  assert_eq(result.text(), "hooked")
  assert_eq(seen_prompts, [Some("hello")])
  // The hook rewrites the dispatched call, not the agent settings.
  assert_eq(agent.settings().temperature, None)
  assert_eq(model.captured_temperatures.val, [Some(0.5)])
}

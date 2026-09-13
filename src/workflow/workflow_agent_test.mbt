///|
async test "workflow agent runs a turn, validates output, and persists the snapshot" {
  let usage : @provider.Usage = {
    input_tokens: 2,
    output_tokens: 1,
    total_tokens: 3,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
  let model = @testing.MockChatModel::new(
    [
      @provider.StreamStart,
      @provider.TextStart("text-0"),
      @provider.TextDelta(id="text-0", delta="{\"answer\":\"Moon it is\"}"),
      @provider.TextEnd("text-0"),
      @provider.Finish(usage~, reason=@provider.Stop),
    ],
    @provider.ChatResponse::new(
      "{\"answer\":\"Moon it is\"}",
      "",
      [],
      usage,
      @provider.Stop,
    ),
  )
  let inner = @agent.ToolLoopAgent::new(
    settings=@agent.ToolLoopAgentSettings::new(
      model=@ai.as_language_model_v4(model as &@provider.ChatModel),
      id="research-agent",
    ),
  )
  let workflow = WorkflowAgent::new(agent=inner as &@agent.Agent, output={
    schema: {
      "type": "object",
      "properties": { "answer": { "type": "string" } },
      "required": ["answer"],
    },
    name: Some("answer-spec"),
  })
  let result = workflow.generate(
    options=@agent.AgentCallOptions::new(prompt="what is Moon?"),
  )
  assert_eq(result.text, "{\"answer\":\"Moon it is\"}")
  guard result.output is Some(output) else { fail("expected validated output") }
  assert_true(output is { "answer": "Moon it is", .. })
  assert_eq(result.steps, 1)
  // Session persistence: user prompt + assistant reply recorded in snapshot.
  assert_eq(result.snapshot.steps, 1)
  assert_eq(result.snapshot.messages.length(), 2)
  assert_eq(result.snapshot.agent_id, Some("research-agent"))
  assert_eq(workflow.messages().length(), 2)
  // Snapshot survives a JSON roundtrip.
  let restored = workflow_snapshot_from_json(workflow.snapshot())
  assert_eq(restored.messages.length(), 2)
  assert_eq(restored.messages[1].content, "{\"answer\":\"Moon it is\"}")
}

///|
async test "workflow agent restore resumes from a persisted snapshot" {
  let usage : @provider.Usage = {
    input_tokens: 1,
    output_tokens: 1,
    total_tokens: 2,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
  let model = @testing.MockChatModel::new(
    [@provider.StreamStart, @provider.Finish(usage~, reason=@provider.Stop)],
    @provider.ChatResponse::new("continued", "", [], usage, @provider.Stop),
  )
  let inner = @agent.ToolLoopAgent::new(
    settings=@agent.ToolLoopAgentSettings::new(
      model=@ai.as_language_model_v4(model as &@provider.ChatModel),
      id="resume-agent",
    ),
  )
  let workflow = WorkflowAgent::new(agent=inner as &@agent.Agent)
  workflow.restore(snapshot={
    agent_id: Some("resume-agent"),
    messages: [
      @provider_utils.ModelMessage::user("first"),
      @provider_utils.ModelMessage::assistant("first reply"),
    ],
    steps: 3,
  })
  let result = workflow.generate(
    options=@agent.AgentCallOptions::new(prompt="second"),
  )
  assert_eq(result.steps, 4)
  assert_eq(result.snapshot.messages.length(), 4)
  assert_eq(result.snapshot.messages[0].content, "first")
  assert_eq(result.snapshot.messages[3].content, "continued")
}

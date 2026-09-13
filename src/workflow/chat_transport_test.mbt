///|
async test "workflow chat transport emits ui chunks and persists snapshot" {
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
    @provider.ChatResponse::new(
      "{\"answer\":\"done\"}",
      "",
      [],
      usage,
      @provider.Stop,
    ),
  )
  let inner = @agent.ToolLoopAgent::new(
    settings=@agent.ToolLoopAgentSettings::new(
      model=@ai.as_language_model_v4(model as &@provider.ChatModel),
      id="chat-agent",
    ),
  )
  let workflow = WorkflowAgent::new(agent=inner as &@agent.Agent)
  let transport = WorkflowChatTransport::new(agent=workflow)
  let response = transport.send_messages(prompt="go")
  let types : Array[String] = []
  for chunk in response.chunks {
    match chunk {
      { "type": String(kind), .. } => types.push(kind)
      _ => ()
    }
  }
  assert_eq(types, ["text-start", "text-delta", "text-end", "finish"])
  assert_eq(response.steps, 1)
  // Reconnect replays the assistant reply from the persisted snapshot.
  let replayed = transport.reconnect_to_stream(snapshot_json=response.snapshot)
  let replay_types : Array[String] = []
  for chunk in replayed {
    match chunk {
      { "type": String(kind), .. } => replay_types.push(kind)
      _ => ()
    }
  }
  assert_eq(replay_types, ["text-start", "text-delta", "text-end", "finish"])
  assert_true(
    replayed[1]
    is { "type": "text-delta", "delta": "{\"answer\":\"done\"}", .. },
  )
}

///|
test "workflow tool approval secret resolves from the environment" {
  let resolved = resolve_workflow_tool_approval_secret(secret={
    environment_variable: "PATH",
  })
  assert_true(resolved != "")
}

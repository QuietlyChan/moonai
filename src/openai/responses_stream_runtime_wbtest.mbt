///|
test "OpenAI Responses runtime shares stream guard state with its decoder" {
  let runtime = openai_responses_stream_runtime(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    false,
    store=true,
    id_generator=() => "test-id",
    approval_tool_call_ids=Map([]),
  )
  ignore(
    runtime.decoder.feed_line(
      "data: {\"type\":\"response.in_progress\",\"response\":{\"id\":\"resp-1\",\"status\":\"in_progress\"}}",
    ),
  )
  ignore(runtime.decoder.feed_line(""))
  assert_true(runtime.stream_guard.is_accepted())
  assert_false(runtime.stream_guard.has_output())
}

///|
test "OpenAI Responses stream metadata uses Azure namespace" {
  let runtime = openai_responses_stream_runtime(
    "azure.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    false,
    store=true,
    id_generator=() => "test-id",
    approval_tool_call_ids=Map([]),
  )
  ignore(
    runtime.decoder.feed_line(
      "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-azure\",\"created_at\":1700000000,\"model\":\"gpt-4o\"}}",
    ),
  )
  ignore(runtime.decoder.feed_line(""))
  ignore(
    runtime.decoder.feed_line(
      "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-azure\",\"created_at\":1700000000,\"model\":\"gpt-4o\",\"output\":[],\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}",
    ),
  )
  ignore(runtime.decoder.feed_line(""))
  json_inspect(runtime.decoder.provider_metadata_snapshot(), content={
    "azure": { "responseId": "resp-azure" },
  })
  json_inspect(runtime.v4_metadata.text_metadata("message-azure", false), content={
    "azure": { "itemId": "message-azure" },
  })
}

///|
test "OpenAI Responses stream maps refusal content to content filter" {
  let runtime = openai_responses_stream_runtime(
    "openai.responses",
    @provider_utils.ToolNameMapping::identity(),
    false,
    false,
    store=true,
    id_generator=() => "test-id",
    approval_tool_call_ids=Map([]),
  )
  let _ = runtime.feed_line(
    "data: {\"type\":\"response.refusal.delta\",\"item_id\":\"message-refusal\",\"delta\":\"Cannot help.\"}",
  )
  let _ = runtime.feed_line("")
  let _ = runtime.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"id\":\"message-refusal\",\"content\":[{\"type\":\"refusal\",\"refusal\":\"Cannot help.\"}]}]}}",
  )
  let terminal = runtime.feed_line("")
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishContentFilter, .. },
        ..
      )
    }),
  )
}

///|
test "model messages are distinct from provider language-model messages" {
  let options : Map[String, Json] = {
    "openai": { "cacheControl": { "type": "ephemeral" } },
  }
  let message = ModelMessage::user_parts(
    [
      ModelContentPart::image_url("https://example.com/image.png").with_provider_options(
        options,
      ),
    ],
    provider_options=options,
  )
  let copy = message.copy()
  copy.parts.push(ModelContentPart::text("later"))
  assert_eq(message.parts.length(), 1)
  assert_eq(copy.parts.length(), 2)
  assert_true(message.provider_options.get("openai") is Some(_))
  assert_true(message.parts[0].provider_options().get("openai") is Some(_))
}

///|
test "assistant model tool calls keep structured JSON input" {
  let message = ModelMessage::assistant("", tool_calls=[
    ModelToolCall::new(id="call-1", name="weather", input={ "city": "Shanghai" }),
  ])
  assert_eq(message.tool_calls.length(), 1)
  assert_eq(message.tool_calls[0].input, { "city": "Shanghai" })
}

///|
test "model messages preserve tool result and approval content" {
  let result = ModelToolResult::json(
    tool_call_id="call-1",
    tool_name="weather",
    value={ "temperature": 18 },
  )
  let approval = ModelToolApprovalResponse::new(
    approval_id="approval-1",
    approved=true,
    provider_executed=true,
  )
  let message = ModelMessage::tool_content([
    ModelContentPart::tool_result(result),
    ModelContentPart::tool_approval_response(approval),
  ])
  assert_eq(message.parts.length(), 2)
  assert_true(message.parts[0] is ModelToolResultPart(_))
  assert_true(message.parts[1] is ModelToolApprovalResponsePart(_))
}

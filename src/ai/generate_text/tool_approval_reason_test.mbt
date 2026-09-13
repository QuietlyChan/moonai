///|
fn approval_reason_test_tool(executions : Ref[Int]) -> @provider_utils.ToolSet {
  @provider_utils.tool_set([
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
}

///|
async test "tool approval requests carry the policy reason (#19658)" {
  let executions : Ref[Int] = Ref(0)
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
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    messages=[@provider_utils.ModelMessage::user("remove the draft")],
    tools=approval_reason_test_tool(executions),
    tool_approval=ToolApprovalConfiguration::per_tool(
      Map([
        (
          "shell",
          ToolApprovalRule::status(
            ToolApprovalStatus::user_approval(
              reason="policy: destructive commands need sign-off",
            ),
          ),
        ),
      ]),
    ),
  )
  assert_eq(executions.val, 0)
  assert_eq(result.tool_approval_requests.length(), 1)
  assert_eq(
    result.tool_approval_requests[0].request_reason,
    Some("policy: destructive commands need sign-off"),
  )
  // The reason survives the persisted-message round trip.
  let request_parts : Array[@provider_utils.ModelToolApprovalRequest] = []
  for wrapped_part in result.response_messages[0].parts {
    match wrapped_part.without_provider_options() {
      @provider_utils.ModelToolApprovalRequestPart(request~) =>
        request_parts.push(request)
      _ => ()
    }
  }
  assert_eq(request_parts.length(), 1)
  assert_eq(
    request_parts[0].request_reason,
    Some("policy: destructive commands need sign-off"),
  )
}

///|
async test "tool approval requests without a policy reason stay reasonless" {
  let executions : Ref[Int] = Ref(0)
  let model = SequenceLanguageModel::new([
    generation_result(
      [generated_tool_call("call-approval", "shell", "{\"command\":\"ls\"}")],
      1,
      1,
      @provider.V4FinishToolCalls,
    ),
  ])
  let result = generate_text(
    model as &@provider.LanguageModelV4,
    messages=[@provider_utils.ModelMessage::user("list files")],
    tools=approval_reason_test_tool(executions),
    tool_approval=ToolApprovalConfiguration::per_tool(
      Map([
        ("shell", ToolApprovalRule::status(ToolApprovalStatus::user_approval())),
      ]),
    ),
  )
  assert_eq(result.tool_approval_requests.length(), 1)
  assert_eq(result.tool_approval_requests[0].request_reason, None)
}

///|
test "reasoning budget follows AI SDK percentages and clamps bounds" {
  let warnings : Array[@provider.Warning] = []
  assert_eq(
    @provider_utils.map_reasoning_to_provider_budget(
      @provider.Medium,
      64_000,
      64_000,
      warnings,
    ),
    Some(19_200),
  )
  assert_eq(warnings, [])

  assert_eq(
    @provider_utils.map_reasoning_to_provider_budget(
      @provider.Minimal,
      10_000,
      10_000,
      warnings,
    ),
    Some(1_024),
  )
  assert_eq(
    @provider_utils.map_reasoning_to_provider_budget(
      @provider.XHigh,
      64_000,
      50_000,
      warnings,
    ),
    Some(50_000),
  )
}

///|
test "reasoning utility distinguishes default and disabled" {
  assert_false(@provider_utils.is_custom_reasoning(@provider.ProviderDefault))
  assert_true(@provider_utils.is_custom_reasoning(@provider.Disabled))
  let warnings : Array[@provider.Warning] = []
  assert_eq(
    @provider_utils.map_reasoning_to_provider_budget(
      @provider.Disabled,
      16_384,
      16_384,
      warnings,
    ),
    None,
  )
  assert_eq(warnings, [])
}

///|
test "assistant reasoning utility prefers content parts over legacy field" {
  let from_part = @provider.LanguageModelMessage::assistant_parts(
    [
      @provider.LanguageModelContentPart::reasoning("first"),
      @provider.LanguageModelContentPart::reasoning(" second"),
      @provider.LanguageModelContentPart::text("answer"),
    ],
    reasoning_content="legacy",
  )
  assert_eq(
    @provider_utils.assistant_reasoning_content(from_part),
    Some("first second"),
  )

  let from_legacy = @provider.LanguageModelMessage::assistant(
    "answer",
    reasoning_content="legacy",
  )
  assert_eq(
    @provider_utils.assistant_reasoning_content(from_legacy),
    Some("legacy"),
  )
  assert_eq(
    @provider_utils.assistant_reasoning_content(
      @provider.LanguageModelMessage::user("hello"),
    ),
    None,
  )
}

///|
test "reasoning effort utility reports compatibility and unsupported levels" {
  let warnings : Array[@provider.Warning] = []
  let mapped = @provider_utils.map_reasoning_to_provider_effort(
    @provider.XHigh,
    { "xhigh": "max" },
    warnings,
  )
  assert_eq(mapped, Some("max"))
  assert_eq(
    warnings[0],
    @provider.Compatibility(
      feature="reasoning",
      details="reasoning \"xhigh\" is not directly supported by this model. mapped to effort \"max\".",
    ),
  )

  let missing = @provider_utils.map_reasoning_to_provider_effort(
    @provider.High,
    { "low": "low" },
    warnings,
  )
  assert_eq(missing, None)
  assert_true(warnings[1] is @provider.Unsupported(..))
}

///|
test "tool approval-only message is identified for Chat Completions adapters" {
  let approval = @provider.LanguageModelToolApprovalResponse::new(
    approval_id="approval-1",
    approved=true,
  )
  let approval_only = @provider.LanguageModelMessage::tool_content([
    @provider.LanguageModelContentPart::tool_approval_response(approval),
  ])
  assert_true(@provider_utils.is_tool_approval_only_message(approval_only))
  let result = @provider.LanguageModelToolResult::text(
    tool_call_id="call-1",
    tool_name="lookup",
    value="ok",
  )
  let mixed = @provider.LanguageModelMessage::tool_content([
    @provider.LanguageModelContentPart::tool_result(result),
    @provider.LanguageModelContentPart::tool_approval_response(approval),
  ])
  assert_false(@provider_utils.is_tool_approval_only_message(mixed))
}

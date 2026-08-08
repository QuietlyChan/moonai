///|
test "V4 prompt tool calls keep structured input across the legacy bridge" {
  let legacy = LanguageModelMessage::assistant_parts([
    LanguageModelContentPart::tool_call(
      ToolCall::new(
        id="call-1",
        name="weather",
        arguments="{\"city\":\"Hangzhou\"}",
      ),
    ),
  ])
  let prompt = LanguageModelV4Prompt::from_language_model_prompt([legacy])
  match prompt.messages[0] {
    V4AssistantMessage(content=[V4PromptToolCall(call)], ..) => {
      assert_eq(call.tool_call_id, "call-1")
      assert_eq(call.tool_name, "weather")
      json_inspect(call.input, content={ "city": "Hangzhou" })
      assert_eq(call.provider_executed, false)
    }
    _ => fail("expected one independent V4 prompt tool call")
  }
  let round_trip = prompt.to_language_model_prompt()
  match round_trip[0].parts[0] {
    ToolCallPart(call) =>
      json_inspect(@json.parse(call.arguments), content={ "city": "Hangzhou" })
    _ => fail("expected a normalized tool-call part")
  }
}

///|
test "V4 prompt filters AI-layer approval requests and local approvals" {
  let approval_request : LanguageModelToolApprovalRequest = {
    approval_id: "approval-1",
    tool_call_id: "call-1",
    is_automatic: false,
    signature: None,
  }
  let prompt = LanguageModelV4Prompt::from_language_model_prompt([
    LanguageModelMessage::assistant_parts([
      LanguageModelContentPart::tool_approval_request(approval_request),
    ]),
    LanguageModelMessage::tool_parts("call-1", [
      LanguageModelContentPart::tool_approval_response(
        LanguageModelToolApprovalResponse::new(
          approval_id="approval-1",
          approved=true,
        ),
      ),
    ]),
    LanguageModelMessage::tool_parts("call-2", [
      LanguageModelContentPart::tool_approval_response(
        LanguageModelToolApprovalResponse::new(
          approval_id="approval-2",
          approved=false,
          provider_executed=true,
        ),
      ),
    ]),
  ])
  assert_eq(prompt.messages.length(), 2)
  assert_true(
    prompt.messages[0] is V4AssistantMessage(content~, ..) &&
    content.length() == 0,
  )
  assert_true(
    prompt.messages[1]
    is V4ToolMessage(
      content=[
        V4PromptToolApprovalResponse(
          { approval_id: "approval-2", approved: false, .. }
        ),
      ],
      ..
    ),
  )
}

///|
test "V4 prompt raw file bytes lower to Base64 only at the legacy boundary" {
  let prompt = LanguageModelV4Prompt::new([
    V4UserMessage(
      content=[
        V4PromptFile(
          data=V4FileBytes(b"PDFDATA"),
          media_type="application/pdf",
          filename=Some("report.pdf"),
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
    V4ToolMessage(
      content=[
        V4PromptToolResult(
          LanguageModelV4ToolResultPart::content(
            tool_call_id="call-1",
            tool_name="read",
            value=[
              LanguageModelV4ToolResultContentPart::file(
                data=V4FileBytes(b"PDFDATA"),
                media_type="application/pdf",
                filename="report.pdf",
              ),
            ],
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let legacy = prompt.to_language_model_prompt()
  assert_true(
    legacy[0].parts[0]
    is FileData(
      data="UERGREFUQQ==",
      media_type="application/pdf",
      filename="report.pdf"
    ),
  )
  match legacy[1].parts[0] {
    ToolResultPart({ output: LanguageModelToolContent(value~, ..), .. }) =>
      assert_true(
        value[0]
        is LanguageModelToolFileData(
          data="UERGREFUQQ==",
          media_type="application/pdf",
          filename="report.pdf",
          ..
        ),
      )
    _ => fail("expected a Base64-normalized tool result")
  }
}

///|
test "V4 content converts all normalized response variants explicitly" {
  let tool_call = ToolCall::new(
    id="call-1",
    name="lookup",
    arguments="{\"query\":\"moon\"}",
    provider_executed=true,
    dynamic=true,
    provider_metadata={ "test": { "call": true } },
  )
  let tool_result = ToolResult::new(
    tool_call_id="call-1",
    tool_name="lookup",
    result={ "answer": 42 },
    preliminary=true,
    dynamic=true,
    provider_metadata={ "test": { "result": true } },
  )
  let approval = ToolApprovalRequest::new(
    approval_id="approval-1",
    tool_call_id="call-1",
    provider_metadata={ "test": { "approval": true } },
  )
  let normalized : Array[GeneratedContent] = [
    GeneratedContent::text("answer", provider_metadata={
      "test": { "text": true },
    }),
    GeneratedContent::reasoning("plan", provider_metadata={
      "test": { "reasoning": true },
    }),
    GeneratedContent::custom(kind="test.block", provider_metadata={
      "test": { "custom": true },
    }),
    GeneratedContent::reasoning_file(
      media_type="image/png",
      data=GeneratedFileUrl("https://example.com/reasoning.png"),
      provider_metadata={ "test": { "reasoningFile": true } },
    ),
    GeneratedContent::file(
      media_type="application/pdf",
      data=GeneratedFileBase64("UERG"),
      provider_metadata={ "test": { "file": true } },
    ),
    GeneratedContent::tool_approval_request(approval),
    GeneratedContent::url_source(
      id="source-1",
      url="https://example.com/source",
      title="Source",
      provider_metadata={ "test": { "source": true } },
    ),
    GeneratedContent::document_source(
      id="document-1",
      media_type="application/pdf",
      title="Document",
      filename="document.pdf",
      provider_metadata={ "test": { "document": true } },
    ),
    GeneratedContent::tool_call(tool_call),
    GeneratedContent::tool_result(tool_result),
  ]

  let v4 = LanguageModelV4Content::from_generated_content_array(normalized)
  assert_true(v4[0] is V4TextOutput(_))
  assert_true(v4[1] is V4ReasoningOutput(_))
  assert_true(v4[2] is V4CustomOutput(_))
  assert_true(v4[3] is V4ReasoningFileOutput(_))
  assert_true(v4[4] is V4FileOutput(_))
  assert_true(v4[5] is V4ToolApprovalRequestOutput(_))
  assert_true(v4[6] is V4SourceOutput(V4UrlSource(..)))
  assert_true(v4[7] is V4SourceOutput(V4DocumentSource(..)))
  assert_true(v4[8] is V4ToolCallOutput(_))
  assert_true(v4[9] is V4ToolResultOutput(_))
  assert_eq(LanguageModelV4Content::to_generated_content_array(v4), normalized)
}

///|
test "V4 generated files retain bytes until the legacy response boundary" {
  let content = LanguageModelV4Content::file(
    media_type="image/png",
    data=V4GeneratedFileBytes(b"PNG"),
  )
  match content {
    V4FileOutput({ data: V4GeneratedFileBytes(value), .. }) =>
      assert_eq(value, b"PNG")
    _ => fail("expected byte-backed V4 file")
  }
  match content.to_generated_content() {
    GeneratedFileOutput({ data: GeneratedFileBase64(value), .. }) =>
      assert_eq(value, "UE5H")
    _ => fail("expected Base64 at the normalized legacy boundary")
  }
}

///|
test "V4 stream conversion exposes V4 tool-call field names" {
  let converted = LanguageModelV4StreamPart::from_stream_event(
    ToolCallReady(
      ToolCall::new(
        id="call-1",
        name="lookup",
        arguments="{\"query\":\"moon\"}",
      ),
    ),
  )
  match converted {
    Some(V4ToolCallReady(call)) => {
      assert_eq(call.tool_call_id, "call-1")
      assert_eq(call.tool_name, "lookup")
      assert_eq(call.input, "{\"query\":\"moon\"}")
    }
    _ => fail("expected a converted V4 tool call")
  }
}

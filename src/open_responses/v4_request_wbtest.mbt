///|
test "native V4 request converts prompt without ChatCallOptions" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(content="Be concise", provider_options=Map([])),
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(text="Read this", provider_options=Map([])),
        @provider.V4PromptFile(
          data=@provider.V4FileData("UERGREFUQQ=="),
          media_type="application/pdf",
          filename=Some("report.pdf"),
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptText(
          text="I will inspect it.",
          provider_options=Map([]),
        ),
        @provider.V4PromptToolCall(
          @provider.ToolCall::new(
            id="call-1",
            name="inspect_pdf",
            arguments="{\"page\":1}",
          ),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4ToolMessage(
      content=[
        @provider.V4PromptToolResult(
          @provider.LanguageModelToolResult::json(
            tool_call_id="call-1",
            tool_name="inspect_pdf",
            value={ "title": "MoonBit" },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let options = @provider.LanguageModelV4CallOptions::new(
    prompt,
    reasoning_effort=@provider.Minimal,
    top_k=40.0,
    provider_options=OpenResponsesLanguageModelOptions::new(
      reasoning_summary=ReasoningSummaryDetailed,
    ).to_provider_options(provider_name="local"),
  )
  let prepared = prepare_open_responses_v4_request(
    "model", options, "local", false,
  )
  json_inspect(prepared.body, content={
    "model": "model",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [
          { "type": "input_text", "text": "Read this" },
          {
            "type": "input_file",
            "filename": "report.pdf",
            "file_data": "data:application/pdf;base64,UERGREFUQQ==",
          },
        ],
      },
      {
        "type": "message",
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "I will inspect it." }],
      },
      {
        "type": "function_call",
        "call_id": "call-1",
        "name": "inspect_pdf",
        "arguments": "{\"page\":1}",
      },
      {
        "type": "function_call_output",
        "call_id": "call-1",
        "output": "{\"title\":\"MoonBit\"}",
      },
    ],
    "instructions": "Be concise",
    "reasoning": { "summary": "detailed", "effort": "low" },
  })
  assert_eq(prepared.warnings.length(), 2)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_true(
    prepared.warnings[1]
    is @provider.Compatibility(feature="reasoningEffort", ..),
  )
}

///|
test "native V4 request rejects provider file references with typed error" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptFile(
            data=@provider.V4FileReference(
              @provider.ProviderReference::single(provider="other", id="file-1"),
            ),
            media_type="application/pdf",
            filename=None,
            provider_options=Map([]),
          ),
        ],
        provider_options=Map([]),
      ),
    ]),
  )
  try
    prepare_open_responses_v4_request("model", options, "openResponses", false)
  catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_eq(functionality, "file parts with provider references")
    error => fail("unexpected provider-reference error: \{error}")
  } noraise {
    _ => fail("expected provider-reference content to be rejected")
  }
}

///|
test "native V4 request warns and skips referenced tool output" {
  let result = @provider.LanguageModelToolResult::content(
    tool_call_id="call-1",
    tool_name="inspect",
    value=[
      @provider.LanguageModelToolFileReference(
        reference=@provider.ProviderReference::single(
          provider="other",
          id="file-1",
        ),
        media_type="application/pdf",
        filename="report.pdf",
        provider_options=Map([]),
      ),
      @provider.LanguageModelToolText(text="kept", provider_options=Map([])),
    ],
  )
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4ToolMessage(
        content=[@provider.V4PromptToolResult(result)],
        provider_options=Map([]),
      ),
    ]),
  )
  let prepared = prepare_open_responses_v4_request(
    "model", options, "openResponses", false,
  )
  json_inspect(prepared.body, content={
    "model": "model",
    "input": [
      {
        "type": "function_call_output",
        "call_id": "call-1",
        "output": [{ "type": "input_text", "text": "kept" }],
      },
    ],
  })
  assert_eq(prepared.warnings, [
    @provider.Other(
      message="unsupported tool content part type: file with data type: reference",
    ),
  ])
}

///|
test "Open Responses V4 usage stays unknown when provider omits usage" {
  let usage = open_responses_v4_usage_from_json(None)
  assert_eq(usage.input_tokens.total, None)
  assert_eq(usage.input_tokens.no_cache, None)
  assert_eq(usage.output_tokens.total, None)
  assert_eq(usage.output_tokens.text, None)
}

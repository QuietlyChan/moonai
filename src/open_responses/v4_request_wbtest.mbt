///|
test "native V4 request converts prompt without ChatCallOptions" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(content="Be concise", provider_options=Map([])),
    @provider.V4SystemMessage(
      content="Use tools carefully",
      provider_options=Map([]),
    ),
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(text="Read this", provider_options=Map([])),
        @provider.V4PromptFile(
          data=@provider.V4FileBytes(b"PDFDATA"),
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
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="call-1",
            tool_name="inspect_pdf",
            input={ "page": 1 },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4ToolMessage(
      content=[
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
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
    reasoning=@provider.V4ReasoningMinimal,
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
    "instructions": "Be concise\nUse tools carefully",
    "reasoning": { "summary": "detailed", "effort": "low" },
  })
  assert_eq(prepared.warnings.length(), 2)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_true(
    prepared.warnings[1]
    is @provider.Compatibility(
      feature="reasoning",
      details="reasoning \"minimal\" is not directly supported by this model. mapped to effort \"low\"."
    ),
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
test "native V4 request ignores unsupported tool approval responses" {
  let approval = @provider.LanguageModelV4ToolApprovalResponsePart::new(
    approval_id="approval-v4",
    approved=false,
    reason="needs review",
  )
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4ToolMessage(
        content=[@provider.V4PromptToolApprovalResponse(approval)],
        provider_options=Map([]),
      ),
    ]),
  )
  let prepared = prepare_open_responses_v4_request(
    "model", options, "openResponses", false,
  )
  json_inspect(prepared.body, content={ "model": "model", "input": [] })
}

///|
test "native V4 request warns and skips referenced tool output" {
  let result = @provider.LanguageModelV4ToolResultPart::content(
    tool_call_id="call-1",
    tool_name="inspect",
    value=[
      @provider.V4ToolResultFileContent(
        data=@provider.V4FileReference(
          @provider.ProviderReference::single(provider="other", id="file-1"),
        ),
        media_type="application/pdf",
        filename=Some("report.pdf"),
        provider_options=Map([]),
      ),
      @provider.V4ToolResultTextContent(text="kept", provider_options=Map([])),
      @provider.V4ToolResultFileContent(
        data=@provider.V4FileUrl("https://example.com/chart.png"),
        media_type="image/png",
        filename=None,
        provider_options=Map([]),
      ),
      @provider.V4ToolResultFileContent(
        data=@provider.V4FileUrl("https://example.com/report.pdf"),
        media_type="application/pdf",
        filename=Some("report.pdf"),
        provider_options=Map([]),
      ),
      @provider.V4ToolResultFileContent(
        data=@provider.V4FileData("iVBORw0KGgo="),
        media_type="image/*",
        filename=None,
        provider_options=Map([]),
      ),
      @provider.V4ToolResultFileContent(
        data=@provider.V4FileBytes(b"PDF"),
        media_type="application/pdf",
        filename=Some("inline.pdf"),
        provider_options=Map([]),
      ),
      @provider.V4ToolResultCustomContent(provider_options=Map([])),
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
        "output": [
          { "type": "input_text", "text": "kept" },
          {
            "type": "input_image",
            "image_url": "https://example.com/chart.png",
          },
          { "type": "input_file", "file_url": "https://example.com/report.pdf" },
          {
            "type": "input_image",
            "image_url": "data:image/png;base64,iVBORw0KGgo=",
          },
          {
            "type": "input_file",
            "filename": "inline.pdf",
            "file_data": "data:application/pdf;base64,UERG",
          },
        ],
      },
    ],
  })
  assert_eq(prepared.warnings, [
    @provider.Other(
      message="unsupported tool content part type: file with data type: reference",
    ),
    @provider.Other(message="unsupported tool content part type: custom"),
  ])
}

///|
test "native V4 request preserves tools sampling and structured output" {
  let schema : Json = {
    "type": "object",
    "properties": { "answer": { "type": "string" } },
    "required": ["answer"],
  }
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptText(text="answer", provider_options=Map([])),
        ],
        provider_options=Map([]),
      ),
    ]),
    tools=[
      @provider.LanguageModelV4Tool::function(
        "lookup",
        { "type": "object" },
        description="Look up an answer",
        strict=false,
      ),
      @provider.LanguageModelV4Tool::provider(
        id="provider.search",
        name="provider_search",
      ),
    ],
    tool_choice=@provider.V4ToolChoiceTool("lookup"),
    response_format=@provider.LanguageModelV4ResponseFormat::json(
      schema~,
      name="answer_schema",
      description="Structured answer",
    ),
    reasoning=@provider.V4ReasoningNone,
    max_output_tokens=256,
    temperature=0.4,
    top_p=0.8,
    frequency_penalty=-0.1,
    presence_penalty=0.2,
  )
  let prepared = prepare_open_responses_v4_request(
    "model", options, "openResponses", true,
  )
  json_inspect(prepared.body, content={
    "model": "model",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "answer" }],
      },
    ],
    "stream": true,
    "max_output_tokens": 256,
    "temperature": 0.4,
    "top_p": 0.8,
    "frequency_penalty": -0.1,
    "presence_penalty": 0.2,
    "reasoning": { "effort": "none" },
    "tools": [
      {
        "type": "function",
        "name": "lookup",
        "description": "Look up an answer",
        "parameters": { "type": "object" },
        "strict": false,
      },
    ],
    "tool_choice": { "type": "function", "name": "lookup" },
    "text": {
      "format": {
        "type": "json_schema",
        "name": "answer_schema",
        "description": "Structured answer",
        "schema": {
          "type": "object",
          "properties": { "answer": { "type": "string" } },
          "required": ["answer"],
        },
        "strict": true,
      },
    },
  })
  assert_eq(prepared.warnings, [])
}

///|
test "native V4 request resolves URL and inline media types" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptFile(
            data=@provider.V4FileUrl("https://example.com/image.png"),
            media_type="image",
            filename=None,
            provider_options=Map([]),
          ),
          @provider.V4PromptFile(
            data=@provider.V4FileData("iVBORw0KGgo="),
            media_type="image/*",
            filename=None,
            provider_options=Map([]),
          ),
          @provider.V4PromptFile(
            data=@provider.V4FileUrl("https://example.com/guide.pdf"),
            media_type="application/pdf",
            filename=Some("guide.pdf"),
            provider_options=Map([]),
          ),
          @provider.V4PromptFile(
            data=@provider.V4FileData("JVBERg=="),
            media_type="application",
            filename=None,
            provider_options=Map([]),
          ),
        ],
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
        "type": "message",
        "role": "user",
        "content": [
          {
            "type": "input_image",
            "image_url": "https://example.com/image.png",
          },
          {
            "type": "input_image",
            "image_url": "data:image/png;base64,iVBORw0KGgo=",
          },
          { "type": "input_file", "file_url": "https://example.com/guide.pdf" },
          {
            "type": "input_file",
            "filename": "data",
            "file_data": "data:application/pdf;base64,JVBERg==",
          },
        ],
      },
    ],
  })
}

///|
test "native V4 request rejects text file parts" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptFile(
            data=@provider.V4FileText("plain text"),
            media_type="text/plain",
            filename=Some("notes.txt"),
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
      assert_eq(functionality, "text file parts")
    error => fail("unexpected text-file error: \{error}")
  } noraise {
    _ => fail("expected text file content to be rejected")
  }
}

///|
test "Open Responses V4 usage stays unknown when provider omits usage" {
  let usage = open_responses_v4_usage_from_json(None)
  assert_eq(usage.input_tokens.total, None)
  assert_eq(usage.input_tokens.no_cache, None)
  assert_eq(usage.output_tokens.total, None)
  assert_eq(usage.output_tokens.text, None)
}

///|
test "native V4 request preserves string tool input and tool result variants" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4AssistantMessage(
        content=[
          @provider.V4PromptToolCall(
            @provider.LanguageModelV4ToolCallPart::new(
              tool_call_id="call-input",
              tool_name="lookup",
              input="{\"query\":\"MoonBit\"}",
            ),
          ),
        ],
        provider_options=Map([]),
      ),
      @provider.V4ToolMessage(
        content=[
          @provider.V4PromptToolResult(
            @provider.LanguageModelV4ToolResultPart::text(
              tool_call_id="call-text",
              tool_name="lookup",
              value="Found five items",
            ),
          ),
          @provider.V4PromptToolResult(
            @provider.LanguageModelV4ToolResultPart::error_text(
              tool_call_id="call-error-text",
              tool_name="lookup",
              value="Request timed out",
            ),
          ),
          @provider.V4PromptToolResult(
            @provider.LanguageModelV4ToolResultPart::error_json(
              tool_call_id="call-error-json",
              tool_name="lookup",
              value={ "code": "timeout" },
            ),
          ),
          @provider.V4PromptToolResult(
            @provider.LanguageModelV4ToolResultPart::execution_denied(
              tool_call_id="call-denied",
              tool_name="delete_file",
              reason="User declined the action",
            ),
          ),
        ],
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
        "type": "function_call",
        "call_id": "call-input",
        "name": "lookup",
        "arguments": "{\"query\":\"MoonBit\"}",
      },
      {
        "type": "function_call_output",
        "call_id": "call-text",
        "output": "Found five items",
      },
      {
        "type": "function_call_output",
        "call_id": "call-error-text",
        "output": "Request timed out",
      },
      {
        "type": "function_call_output",
        "call_id": "call-error-json",
        "output": "{\"code\":\"timeout\"}",
      },
      {
        "type": "function_call_output",
        "call_id": "call-denied",
        "output": "User declined the action",
      },
    ],
  })
  assert_eq(prepared.warnings, [])
}

///|
test "native V4 request maps auto tool choice and schema-free JSON output" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptText(text="answer", provider_options=Map([])),
        ],
        provider_options=Map([]),
      ),
    ]),
    tool_choice=@provider.V4ToolChoiceAuto,
    response_format=@provider.LanguageModelV4ResponseFormat::json_object(),
    stop_sequences=["END"],
  )
  let prepared = prepare_open_responses_v4_request(
    "model", options, "openResponses", false,
  )
  json_inspect(prepared.body, content={
    "model": "model",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "answer" }],
      },
    ],
    "tool_choice": "auto",
    "text": { "format": { "type": "json_schema" } },
  })
  assert_eq(prepared.warnings.length(), 1)
  assert_true(
    prepared.warnings[0] is @provider.Unsupported(feature="stopSequences", ..),
  )
}

///|
test "native V4 request rejects non-text user content" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptReasoning(
            text="internal reasoning",
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
      assert_eq(
        functionality, "non-text/file parts in Open Responses user messages",
      )
    error => fail("unexpected user-content error: \{error}")
  } noraise {
    _ => fail("expected non-text user content to be rejected")
  }
}

///|
test "native V4 request warns and skips text-file tool output" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4ToolMessage(
        content=[
          @provider.V4PromptToolResult(
            @provider.LanguageModelV4ToolResultPart::content(
              tool_call_id="call-1",
              tool_name="inspect",
              value=[
                @provider.V4ToolResultFileContent(
                  data=@provider.V4FileText("plain text"),
                  media_type="text/plain",
                  filename=Some("notes.txt"),
                  provider_options=Map([]),
                ),
              ],
            ),
          ),
        ],
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
      { "type": "function_call_output", "call_id": "call-1", "output": [] },
    ],
  })
  assert_eq(prepared.warnings, [
    @provider.Other(
      message="unsupported tool content part type: file with data type: text",
    ),
  ])
}

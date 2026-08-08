///|
test "Anthropic V4 request consumes the provider prompt directly" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(content="Use the document", provider_options={
      "anthropic.messages": { "cacheControl": { "type": "ephemeral" } },
    }),
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(
          text="Inspect this PDF",
          provider_options=Map([]),
        ),
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
        @provider.V4PromptReasoning(text="I will inspect the first page.", provider_options={
          "anthropic.messages": { "signature": "sig-v4" },
        }),
        @provider.V4PromptText(text="Reading now.", provider_options=Map([])),
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
    tools=[
      @provider.LanguageModelV4Tool::from_tool_definition(
        @provider.ToolDefinition::new("inspect_pdf", {
          "type": "object",
          "properties": { "page": { "type": "integer" } },
        }),
      ),
    ],
    tool_choice=@provider.V4ToolChoiceTool("inspect_pdf"),
    max_output_tokens=512,
  )
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6", options, "anthropic.messages", false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-sonnet-4-6",
    "messages": [
      {
        "role": "user",
        "content": [
          { "type": "text", "text": "Inspect this PDF" },
          {
            "type": "document",
            "source": {
              "type": "base64",
              "media_type": "application/pdf",
              "data": "UERGREFUQQ==",
            },
            "title": "report.pdf",
          },
        ],
      },
      {
        "role": "assistant",
        "content": [
          {
            "type": "thinking",
            "thinking": "I will inspect the first page.",
            "signature": "sig-v4",
          },
          { "type": "text", "text": "Reading now." },
          {
            "type": "tool_use",
            "id": "call-1",
            "name": "inspect_pdf",
            "input": { "page": 1 },
          },
        ],
      },
      {
        "role": "user",
        "content": [
          {
            "type": "tool_result",
            "tool_use_id": "call-1",
            "content": "{\"title\":\"MoonBit\"}",
          },
        ],
      },
    ],
    "max_tokens": 512,
    "system": [
      {
        "type": "text",
        "text": "Use the document",
        "cache_control": { "type": "ephemeral" },
      },
    ],
    "tools": [
      {
        "name": "inspect_pdf",
        "input_schema": {
          "type": "object",
          "properties": { "page": { "type": "integer" } },
        },
      },
    ],
    "tool_choice": { "type": "tool", "name": "inspect_pdf" },
  })
  assert_true(prepared.beta_features.contains("pdfs-2024-09-25"))
}

///|
test "Anthropic V4 request reports unsupported prompt parts as warnings" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4AssistantMessage(
        content=[
          @provider.V4PromptReasoning(text="not sent", provider_options={
            "anthropic.messages": { "redactedData": "opaque" },
          }),
        ],
        provider_options=Map([]),
      ),
    ]),
    provider_options=AnthropicLanguageModelOptions::new(send_reasoning=false).to_provider_options(),
  )
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6", options, "anthropic.messages", false,
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Other(
        message="sending reasoning content is disabled for this model"
      )
    }),
  )
}

///|
test "Anthropic V4 drops initial tool changes with the AI SDK warning" {
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4SystemMessage(content="initial", provider_options={
          "anthropic.messages": {
            "toolChanges": [
              { "type": "tool_addition", "toolName": "get_forecast" },
            ],
          },
        }),
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ]),
    ),
    "anthropic.messages",
    false,
  )
  assert_true(
    prepared.body
    is {
      "system": [{ "type": "text", "text": "initial", .. }],
      "messages": [
        {
          "role": "user",
          "content": [{ "type": "text", "text": "hi", .. }],
          ..
        },
      ],
      ..
    },
  )
  assert_true(
    !prepared.beta_features.contains("mid-conversation-tool-changes-2026-07-01"),
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Other(
        message="tool changes on the initial system message are not supported by Anthropic. Configure the initial tool set via the tools option instead. The tool changes have been ignored."
      )
    }),
  )
}

///|
test "Anthropic V4 hoists the first plain system block after a user block" {
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
        @provider.V4SystemMessage(
          content="be concise",
          provider_options=Map([]),
        ),
      ]),
    ),
    "anthropic.messages",
    false,
  )
  assert_true(
    prepared.body
    is {
      "system": [{ "type": "text", "text": "be concise", .. }],
      "messages": [
        {
          "role": "user",
          "content": [{ "type": "text", "text": "hi", .. }],
          ..
        },
      ],
      ..
    },
  )
  assert_true(
    !prepared.beta_features.contains("mid-conversation-system-2026-04-07"),
  )
}

///|
test "Anthropic V4 keeps a tool-change system block inline as one block" {
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
        @provider.V4SystemMessage(
          content="tools changed",
          provider_options=Map([]),
        ),
        @provider.V4SystemMessage(content="", provider_options={
          "anthropic.messages": {
            "toolChanges": [
              { "type": "tool_removal", "toolName": "get_weather" },
            ],
          },
        }),
      ]),
    ),
    "anthropic.messages",
    false,
  )
  guard prepared.body is Object(fields) else {
    fail("expected an Anthropic request object")
  }
  assert_eq(fields.get("system"), None)
  assert_eq(
    fields.get("messages"),
    Some(
      Json::array([
        { "role": "user", "content": [{ "type": "text", "text": "hi" }] },
        {
          "role": "system",
          "content": [
            { "type": "text", "text": "tools changed" },
            {
              "type": "tool_removal",
              "tool": { "type": "tool_reference", "name": "get_weather" },
            },
          ],
        },
      ]),
    ),
  )
  assert_true(
    prepared.beta_features.contains("mid-conversation-system-2026-04-07"),
  )
  assert_true(
    prepared.beta_features.contains("mid-conversation-tool-changes-2026-07-01"),
  )
}

///|
test "Anthropic V4 warns when JSON Tool mode overrides parallel tool use" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([]),
    response_format=@provider.LanguageModelV4ResponseFormat::json(schema={
      "type": "object",
      "properties": { "name": { "type": "string" } },
    }),
    provider_options=AnthropicLanguageModelOptions::new(
      structured_output_mode=AnthropicStructuredOutputJsonTool,
      disable_parallel_tool_use=false,
    ).to_provider_options(),
  )
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-5", options, "anthropic.messages", false,
  )
  assert_true(prepared.uses_json_response_tool)
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Unsupported(
        feature="providerOptions.anthropic.disableParallelToolUse",
        details=_
      )
    }),
  )
  assert_true(
    prepared.body
    is {
      "tool_choice": {
        "type": String("any"),
        "disable_parallel_tool_use": True,
        ..
      },
      ..
    },
  )
}

///|
test "Anthropic V4 detects implicit code execution for current web tools" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(text="Search the web", provider_options=Map([])),
      ],
      provider_options=Map([]),
    ),
  ])
  let without_code = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(prompt, tools=[
      @provider.LanguageModelV4Tool::from_tool_definition(
        web_fetch_20260209_tool(),
      ),
    ]),
    "anthropic.messages",
    false,
  )
  assert_eq(without_code.mark_code_execution_dynamic, true)
  let with_code = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(prompt, tools=[
      @provider.LanguageModelV4Tool::from_tool_definition(
        web_fetch_20260209_tool(),
      ),
      @provider.LanguageModelV4Tool::from_tool_definition(
        code_execution_20260120_tool(),
      ),
    ]),
    "anthropic.messages",
    false,
  )
  assert_eq(with_code.mark_code_execution_dynamic, false)
  let with_function_code = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(prompt, tools=[
      @provider.LanguageModelV4Tool::from_tool_definition(
        web_fetch_20260209_tool(),
      ),
      @provider.LanguageModelV4Tool::function("code_execution", {
        "type": "object",
        "properties": Json::empty_object(),
      }),
    ]),
    "anthropic.messages",
    false,
  )
  assert_eq(with_function_code.mark_code_execution_dynamic, false)
}

///|
test "Anthropic V4 preserves malformed tool input and trims only the final assistant prefill" {
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4AssistantMessage(
          content=[
            @provider.V4PromptText(
              text=" earlier assistant  ",
              provider_options=Map([]),
            ),
          ],
          provider_options=Map([]),
        ),
        @provider.V4UserMessage(
          content=[
            @provider.V4PromptText(text="continue", provider_options=Map([])),
          ],
          provider_options=Map([]),
        ),
        @provider.V4AssistantMessage(
          content=[
            @provider.V4PromptToolCall(
              @provider.LanguageModelV4ToolCallPart::new(
                tool_call_id="call-invalid",
                tool_name="lookup",
                input=Json::string("{ \"city\": \"Hangzhou\", }"),
              ),
            ),
            @provider.V4PromptText(
              text=" final answer  ",
              provider_options=Map([]),
            ),
          ],
          provider_options=Map([]),
        ),
      ]),
    ),
    "anthropic.messages",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "claude-sonnet-4-6",
    "messages": [
      {
        "role": "assistant",
        "content": [{ "type": "text", "text": " earlier assistant  " }],
      },
      { "role": "user", "content": [{ "type": "text", "text": "continue" }] },
      {
        "role": "assistant",
        "content": [
          { "type": "text", "text": "final answer" },
          {
            "type": "tool_use",
            "id": "call-invalid",
            "name": "lookup",
            "input": { "rawInvalidInput": "{ \"city\": \"Hangzhou\", }" },
          },
        ],
      },
    ],
    "max_tokens": 128000,
  })
}

///|
test "Anthropic V4 shares the cache breakpoint limit across prompt and tools" {
  let cache_options : Map[String, Json] = {
    "anthropic.messages": { "cacheControl": { "type": "ephemeral" } },
  }
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4SystemMessage(
          content="system one",
          provider_options=cache_options,
        ),
        @provider.V4SystemMessage(
          content="system two",
          provider_options=cache_options,
        ),
        @provider.V4UserMessage(
          content=[
            @provider.V4PromptText(
              text="cached user",
              provider_options=cache_options,
            ),
          ],
          provider_options=Map([]),
        ),
      ]),
      tools=[
        @provider.LanguageModelV4Tool::from_tool_definition(
          @provider.ToolDefinition::new(
            "first_tool",
            { "type": "object" },
            provider_options=cache_options,
          ),
        ),
        @provider.LanguageModelV4Tool::from_tool_definition(
          @provider.ToolDefinition::new(
            "second_tool",
            { "type": "object" },
            provider_options=cache_options,
          ),
        ),
      ],
    ),
    "anthropic.messages",
    false,
  )
  guard prepared.body is Object(fields) else {
    fail("expected an Anthropic request object")
  }
  guard fields.get("tools") is Some(Array(tools)) else {
    fail("expected Anthropic tools")
  }
  assert_eq(tools.length(), 2)
  assert_true(
    tools[0]
    is {
      "name": "first_tool",
      "cache_control": { "type": "ephemeral", .. },
      ..
    },
  )
  guard tools[1] is Object(second_tool) else {
    fail("expected the second Anthropic tool")
  }
  assert_eq(second_tool.get("cache_control"), None)
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Unsupported(
        feature="cacheControl breakpoint limit",
        details="Maximum 4 cache breakpoints exceeded (found 5). This breakpoint will be ignored."
      )
    }),
  )
}

///|
test "Anthropic V4 rejects cache control on thinking blocks" {
  let cache_control : Json = { "type": "ephemeral" }
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4AssistantMessage(
          content=[
            @provider.V4PromptReasoning(text="visible thinking", provider_options={
              "anthropic.messages": {
                "signature": "sig-thinking",
                "cacheControl": cache_control,
              },
            }),
            @provider.V4PromptReasoning(text="redacted thinking", provider_options={
              "anthropic.messages": {
                "redactedData": "opaque-thinking",
                "cacheControl": cache_control,
              },
            }),
          ],
          provider_options=Map([]),
        ),
      ]),
    ),
    "anthropic.messages",
    false,
  )
  guard prepared.body is Object(fields) else {
    fail("expected an Anthropic request object")
  }
  guard fields.get("messages") is Some(Array(messages)) &&
    messages[0] is Object(message) &&
    message.get("content") is Some(Array(content)) else {
    fail("expected Anthropic assistant content")
  }
  guard content[0] is Object(thinking) &&
    content[1] is Object(redacted_thinking) else {
    fail("expected Anthropic thinking blocks")
  }
  assert_eq(thinking.get("cache_control"), None)
  assert_eq(redacted_thinking.get("cache_control"), None)
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Unsupported(
        feature="cache_control on non-cacheable context",
        details="cache_control cannot be set on thinking block. It will be ignored."
      )
    }),
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Unsupported(
        feature="cache_control on non-cacheable context",
        details="cache_control cannot be set on redacted thinking block. It will be ignored."
      )
    }),
  )
}

///|
test "Anthropic moves regular tool uses within reasoning segments" {
  let content : Array[Json] = [
    { "type": "text", "text": "before" },
    { "type": "tool_use", "id": "client-1" },
    { "type": "server_tool_use", "id": "hosted-1" },
    { "type": "web_search_tool_result", "tool_use_id": "hosted-1" },
    { "type": "thinking", "thinking": "next segment" },
    { "type": "tool_use", "id": "client-2" },
    { "type": "text", "text": "after" },
  ]
  move_anthropic_tool_use_blocks_to_end(content)
  json_inspect(Json::array(content), content=[
    { "type": "text", "text": "before" },
    { "type": "server_tool_use", "id": "hosted-1" },
    { "type": "web_search_tool_result", "tool_use_id": "hosted-1" },
    { "type": "tool_use", "id": "client-1" },
    { "type": "thinking", "thinking": "next segment" },
    { "type": "text", "text": "after" },
    { "type": "tool_use", "id": "client-2" },
  ])
}

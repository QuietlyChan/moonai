///|
fn alibaba_test_cache_control() -> Map[String, Json] {
  { "alibaba": { "cacheControl": { "type": "ephemeral" } } }
}

///|
test "Alibaba V4 applies message cache control to the last tool result" {
  let conversion = alibaba_v4_prompt_converter(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4ToolMessage(
        content=[
          @provider.V4PromptToolResult(
            @provider.LanguageModelV4ToolResultPart::json(
              tool_call_id="call-1",
              tool_name="weather",
              value={ "temperature": 24 },
            ),
          ),
          @provider.V4PromptToolApprovalResponse(
            @provider.LanguageModelV4ToolApprovalResponsePart::new(
              approval_id="approval-1",
              approved=true,
            ),
          ),
          @provider.V4PromptToolResult(
            @provider.LanguageModelV4ToolResultPart::text(
              tool_call_id="call-2",
              tool_name="time",
              value="2:30 PM",
            ),
          ),
        ],
        provider_options=alibaba_test_cache_control(),
      ),
    ]),
    "alibaba.chat",
  )
  json_inspect(Json::array(conversion.messages), content=[
    {
      "role": "tool",
      "tool_call_id": "call-1",
      "content": "{\"temperature\":24}",
    },
    {
      "role": "tool",
      "tool_call_id": "call-2",
      "content": [
        {
          "type": "text",
          "text": "2:30 PM",
          "cache_control": { "type": "ephemeral" },
        },
      ],
    },
  ])
  assert_eq(conversion.warnings.length(), 0)
}

///|
test "Alibaba V4 counts overridden cache markers like AI SDK" {
  let parts : Array[@provider.LanguageModelV4PromptPart] = []
  for index = 0; index < 4; index = index + 1 {
    parts.push(
      @provider.V4PromptText(
        text="part-\{index}",
        provider_options=alibaba_test_cache_control(),
      ),
    )
  }
  let conversion = alibaba_v4_prompt_converter(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=parts,
        provider_options=alibaba_test_cache_control(),
      ),
    ]),
    "alibaba.chat",
  )
  assert_eq(conversion.warnings.length(), 1)
  assert_true(
    conversion.warnings[0]
    is @provider.Other(
      message="Max breakpoint limit exceeded. Only the last 4 cache markers will take effect."
    ),
  )
}

///|
test "Alibaba V4 preserves provider options in structured tool output" {
  let result = @provider.LanguageModelV4ToolResultPart::content(
    tool_call_id="call-1",
    tool_name="lookup",
    value=[
      @provider.LanguageModelV4ToolResultContentPart::text("result", provider_options={
        "example": { "citation": "source-1" },
      }),
      @provider.LanguageModelV4ToolResultContentPart::custom(provider_options={
        "example": { "kind": "reference" },
      }),
    ],
  )
  let conversion = alibaba_v4_prompt_converter(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4ToolMessage(
        content=[@provider.V4PromptToolResult(result)],
        provider_options=Map([]),
      ),
    ]),
    "alibaba.chat",
  )
  json_inspect(Json::array(conversion.messages), content=[
    {
      "role": "tool",
      "tool_call_id": "call-1",
      "content": "[{\"type\":\"text\",\"text\":\"result\",\"providerOptions\":{\"example\":{\"citation\":\"source-1\"}}},{\"type\":\"custom\",\"providerOptions\":{\"example\":{\"kind\":\"reference\"}}}]",
    },
  ])
}

///|
test "Alibaba V4 reasoning budget uses the provider context window" {
  let effective = alibaba_apply_reasoning_v4(
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([]),
      reasoning=@provider.V4ReasoningHigh,
      max_output_tokens=100,
    ),
  )
  json_inspect(Json::object(effective.provider_options), content={
    "alibaba": { "enableThinking": true, "thinkingBudget": 9830 },
  })
  assert_true(effective.reasoning is @provider.V4ReasoningProviderDefault)
}

///|
test "Alibaba wire transform keeps only Alibaba chat fields" {
  json_inspect(
    alibaba_transform_chat_body({
      "model": "qwen-plus",
      "messages": [],
      "response_format": {
        "type": "json_schema",
        "json_schema": {
          "name": "response",
          "schema": { "type": "object" },
          "strict": true,
        },
      },
      "parallelToolCalls": false,
      "user": "ignored",
      "vendorFlag": true,
    }),
    content={
      "model": "qwen-plus",
      "messages": [],
      "response_format": {
        "type": "json_schema",
        "json_schema": { "name": "response", "schema": { "type": "object" } },
      },
    },
  )
  json_inspect(
    alibaba_transform_chat_body({
      "model": "qwen-plus",
      "messages": [],
      "tools": [],
      "parallelToolCalls": false,
    }),
    content={
      "model": "qwen-plus",
      "messages": [],
      "tools": [],
      "parallel_tool_calls": false,
    },
  )
}

///|
test "Alibaba V4 converts cached system and multimodal user messages" {
  let conversion = alibaba_v4_prompt_converter(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4SystemMessage(
        content="Be concise.",
        provider_options=alibaba_test_cache_control(),
      ),
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptText(
            text="What is shown?",
            provider_options=Map([]),
          ),
          @provider.V4PromptFile(
            data=@provider.V4FileBytes(b"\x89PNG"),
            media_type="image",
            filename=None,
            provider_options=alibaba_test_cache_control(),
          ),
        ],
        provider_options=Map([]),
      ),
    ]),
    "alibaba.chat",
  )
  json_inspect(Json::array(conversion.messages), content=[
    {
      "role": "system",
      "content": [
        {
          "type": "text",
          "text": "Be concise.",
          "cache_control": { "type": "ephemeral" },
        },
      ],
    },
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "What is shown?" },
        {
          "type": "image_url",
          "image_url": { "url": "data:image/png;base64,iVBORw==" },
          "cache_control": { "type": "ephemeral" },
        },
      ],
    },
  ])
  assert_eq(conversion.warnings, [])
}

///|
test "Alibaba V4 converts assistant text reasoning and tool calls" {
  let conversion = alibaba_v4_prompt_converter(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4AssistantMessage(
        content=[
          @provider.V4PromptReasoning(text="Plan. ", provider_options=Map([])),
          @provider.V4PromptText(text="Checking.", provider_options=Map([])),
          @provider.V4PromptToolCall(
            @provider.LanguageModelV4ToolCallPart::new(
              tool_call_id="call-1",
              tool_name="lookup",
              input={ "city": "Hangzhou" },
            ),
          ),
        ],
        provider_options=alibaba_test_cache_control(),
      ),
      @provider.V4AssistantMessage(
        content=[
          @provider.V4PromptToolCall(
            @provider.LanguageModelV4ToolCallPart::new(
              tool_call_id="call-2",
              tool_name="time",
              input=Json::empty_object(),
            ),
          ),
        ],
        provider_options=Map([]),
      ),
    ]),
    "alibaba.chat",
  )
  json_inspect(Json::array(conversion.messages), content=[
    {
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "Plan. Checking.",
          "cache_control": { "type": "ephemeral" },
        },
      ],
      "tool_calls": [
        {
          "id": "call-1",
          "type": "function",
          "function": {
            "name": "lookup",
            "arguments": "{\"city\":\"Hangzhou\"}",
          },
        },
      ],
    },
    {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        {
          "id": "call-2",
          "type": "function",
          "function": { "name": "time", "arguments": "{}" },
        },
      ],
    },
  ])
  assert_eq(conversion.warnings, [])
}

///|
test "Alibaba V4 rejects unsupported user file inputs" {
  let reference = @provider.ProviderReference::single(
    provider="alibaba",
    id="file-ref-1",
  )
  try
    alibaba_v4_prompt_converter(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[
            @provider.V4PromptFile(
              data=@provider.V4FileReference(reference),
              media_type="image/png",
              filename=None,
              provider_options=Map([]),
            ),
          ],
          provider_options=Map([]),
        ),
      ]),
      "alibaba.chat",
    )
  catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_true(functionality.contains("provider references"))
    error => fail("unexpected Alibaba file reference error: \{error}")
  } noraise {
    _ => fail("expected Alibaba provider file reference rejection")
  }

  try
    alibaba_v4_prompt_converter(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[
            @provider.V4PromptFile(
              data=@provider.V4FileText("document"),
              media_type="text/plain",
              filename=None,
              provider_options=Map([]),
            ),
          ],
          provider_options=Map([]),
        ),
      ]),
      "alibaba.chat",
    )
  catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_true(functionality.contains("Only image"))
    error => fail("unexpected Alibaba text file error: \{error}")
  } noraise {
    _ => fail("expected Alibaba text file rejection")
  }
}

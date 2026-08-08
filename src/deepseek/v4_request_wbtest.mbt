///|
test "DeepSeek V4 request preserves structured provider inputs" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(content="Be concise.", provider_options=Map([])),
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(text="Check the city", provider_options=Map([])),
        @provider.V4PromptFile(
          data=@provider.V4FileBytes(b"image"),
          media_type="image/png",
          filename=None,
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptReasoning(
          text="I should use the tool.",
          provider_options=Map([]),
        ),
        @provider.V4PromptText(text="Checking.", provider_options=Map([])),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="call_1",
            tool_name="lookup",
            input={ "city": "Hangzhou" },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4ToolMessage(
      content=[
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="call_1",
            tool_name="lookup",
            value={ "temperature": 24 },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_deepseek_v4_request(
    "deepseek-reasoner",
    @provider.LanguageModelV4CallOptions::new(
      prompt,
      tools=[
        @provider.LanguageModelV4Tool::function(
          "lookup",
          {
            "type": "object",
            "properties": { "city": { "type": "string" } },
            "required": ["city"],
          },
          description="Look up weather",
          strict=true,
        ),
        @provider.LanguageModelV4Tool::provider(
          id="deepseek.search",
          name="search",
        ),
      ],
      tool_choice=@provider.V4ToolChoiceTool("lookup"),
      response_format=@provider.LanguageModelV4ResponseFormat::json(
        name="weather",
        description="Weather result",
        schema={ "type": "object" },
      ),
      reasoning=@provider.V4ReasoningMinimal,
      max_output_tokens=256,
      top_k=20.0,
      seed=7,
      provider_options={ "deepseek": { "strictJsonSchema": false } },
    ),
    "deepseek.chat",
    true,
    true,
    true,
  )
  json_inspect(prepared.body, content={
    "model": "deepseek-reasoner",
    "messages": [
      { "role": "system", "content": "Be concise." },
      { "role": "user", "content": "Check the city" },
      {
        "role": "assistant",
        "content": "Checking.",
        "reasoning_content": "I should use the tool.",
        "tool_calls": [
          {
            "id": "call_1",
            "type": "function",
            "function": {
              "name": "lookup",
              "arguments": "{\"city\":\"Hangzhou\"}",
            },
          },
        ],
      },
      {
        "role": "tool",
        "tool_call_id": "call_1",
        "content": "{\"temperature\":24}",
      },
    ],
    "stream": true,
    "stream_options": { "include_usage": true },
    "max_tokens": 256,
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "weather",
        "schema": { "type": "object" },
        "strict": false,
        "description": "Weather result",
      },
    },
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "lookup",
          "description": "Look up weather",
          "parameters": {
            "type": "object",
            "properties": { "city": { "type": "string" } },
            "required": ["city"],
          },
          "strict": true,
        },
      },
    ],
    "tool_choice": { "type": "function", "function": { "name": "lookup" } },
    "thinking": { "type": "enabled" },
    "reasoning_effort": "low",
  })
  assert_eq(prepared.warnings.length(), 5)
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Unsupported(feature="user message part type: file", ..)
    }),
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning is @provider.Unsupported(feature="topK", ..)
    }),
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning is @provider.Unsupported(feature="seed", ..)
    }),
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Unsupported(
        feature="provider-defined tool deepseek.search",
        ..
      )
    }),
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning is @provider.Compatibility(feature="reasoning", ..)
    }),
  )
}

///|
test "DeepSeek V4 and R1 apply distinct reasoning history rules" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptReasoning(
          text="historical reasoning",
          provider_options=Map([]),
        ),
        @provider.V4PromptText(text="old answer", provider_options=Map([])),
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
        @provider.V4PromptText(text="new answer", provider_options=Map([])),
      ],
      provider_options=Map([]),
    ),
  ])
  let r1 = convert_v4_prompt_to_deepseek(
    prompt,
    @provider.V4ResponseText,
    "deepseek-reasoner",
    false,
  )
  json_inspect(Json::array(r1.messages), content=[
    { "role": "assistant", "content": "old answer" },
    { "role": "user", "content": "continue" },
    { "role": "assistant", "content": "new answer" },
  ])
  let v4 = convert_v4_prompt_to_deepseek(
    prompt,
    @provider.V4ResponseText,
    "deepseek-v4-preview",
    false,
  )
  json_inspect(Json::array(v4.messages), content=[
    {
      "role": "assistant",
      "content": "old answer",
      "reasoning_content": "historical reasoning",
    },
    { "role": "user", "content": "continue" },
    { "role": "assistant", "content": "new answer", "reasoning_content": "" },
  ])
}

///|
test "DeepSeek V4 preserves provider options in content tool results" {
  let result = @provider.LanguageModelV4ToolResultPart::content(
    tool_call_id="call-content",
    tool_name="inspect",
    value=[
      @provider.LanguageModelV4ToolResultContentPart::text("summary", provider_options={
        "example": { "citation": "source-1" },
      }),
      @provider.LanguageModelV4ToolResultContentPart::file(
        data=@provider.V4FileUrl("https://example.com/report.pdf"),
        media_type="application/pdf",
        filename="report.pdf",
        provider_options={ "example": { "retention": "temporary" } },
      ),
      @provider.LanguageModelV4ToolResultContentPart::custom(provider_options={
        "example": { "kind": "reference" },
      }),
    ],
  )
  let conversion = convert_v4_prompt_to_deepseek(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4ToolMessage(
        content=[@provider.V4PromptToolResult(result)],
        provider_options=Map([]),
      ),
    ]),
    @provider.V4ResponseText,
    "deepseek-chat",
    false,
  )
  match conversion.messages {
    [{ "role": "tool", "content": String(content), .. }] =>
      json_inspect(@json.parse(content), content=[
        {
          "type": "text",
          "text": "summary",
          "providerOptions": { "example": { "citation": "source-1" } },
        },
        {
          "type": "file",
          "data": { "type": "url", "url": "https://example.com/report.pdf" },
          "mediaType": "application/pdf",
          "filename": "report.pdf",
          "providerOptions": { "example": { "retention": "temporary" } },
        },
        {
          "type": "custom",
          "providerOptions": { "example": { "kind": "reference" } },
        },
      ])
    _ => fail("expected one serialized DeepSeek content tool result")
  }
}

///|
test "DeepSeek retains an empty tool list when only provider tools were declared" {
  let prepared = prepare_deepseek_v4_request(
    "deepseek-chat",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[
            @provider.V4PromptText(text="search", provider_options=Map([])),
          ],
          provider_options=Map([]),
        ),
      ]),
      tools=[
        @provider.LanguageModelV4Tool::provider(
          id="deepseek.search",
          name="search",
        ),
      ],
      tool_choice=@provider.V4ToolChoiceRequired,
    ),
    "deepseek.chat",
    false,
    true,
    false,
  )
  json_inspect(prepared.body, content={
    "model": "deepseek-chat",
    "messages": [{ "role": "user", "content": "search" }],
    "tools": [],
    "tool_choice": "required",
  })
  assert_eq(prepared.warnings.length(), 1)
  assert_true(
    prepared.warnings[0]
    is @provider.Warning::Unsupported(
      feature="provider-defined tool deepseek.search",
      ..
    ),
  )
}

///|
test "native V4 request preserves structured prompt and call options" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(content="You are concise.", provider_options={
      "openaiCompatible": { "systemPriority": "high" },
    }),
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(text="Describe the inputs", provider_options={
          "openaiCompatible": { "partPriority": "normal" },
        }),
        @provider.V4PromptFile(
          data=@provider.V4FileBytes(b"image"),
          media_type="image/png",
          filename=None,
          provider_options=Map([]),
        ),
        @provider.V4PromptFile(
          data=@provider.V4FileBytes(b"MoonBit"),
          media_type="text/plain",
          filename=Some("readme.txt"),
          provider_options=Map([]),
        ),
      ],
      provider_options={ "openaiCompatible": { "messagePriority": "normal" } },
    ),
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptReasoning(
          text="Check the city.",
          provider_options=Map([]),
        ),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="call-1",
            tool_name="lookup",
            input={ "city": "Paris" },
            provider_options={
              "openaiCompatible": { "toolPriority": "critical" },
              "google": { "thoughtSignature": "signature-1" },
            },
          ),
        ),
      ],
      provider_options={ "openaiCompatible": { "assistantPriority": "high" } },
    ),
    @provider.V4ToolMessage(
      content=[
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="call-1",
            tool_name="lookup",
            value={ "temperature": 21 },
            provider_options={ "openaiCompatible": { "resultTier": "fresh" } },
          ),
        ),
        @provider.V4PromptToolApprovalResponse(
          @provider.LanguageModelV4ToolApprovalResponsePart::new(
            approval_id="approval-1",
            approved=true,
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let options = @provider.LanguageModelV4CallOptions::new(
    prompt,
    tools=[
      @provider.LanguageModelV4Tool::function(
        "lookup",
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        description="Look up a city",
        strict=true,
      ),
      @provider.LanguageModelV4Tool::provider(
        id="provider.search",
        name="provider_search",
      ),
    ],
    tool_choice=@provider.V4ToolChoiceTool("lookup"),
    response_format=@provider.LanguageModelV4ResponseFormat::json(
      name="answer",
      schema={ "type": "object" },
    ),
    reasoning=@provider.V4ReasoningHigh,
    top_k=20.0,
    frequency_penalty=0.5,
    include_raw_chunks=true,
    provider_options={
      "openaiCompatible": { "textVerbosity": "low", "user": "generic" },
      "localTest": { "user": "custom", "vendorFlag": true },
    },
  )
  let prepared = prepare_compatible_v4_chat_request(
    "test-model", options, true, true, "local-test.chat", true, false, false, default_openai_compatible_v4_prompt_converter,
  )
  json_inspect(prepared.body, content={
    "model": "test-model",
    "messages": [
      {
        "role": "system",
        "content": "You are concise.",
        "systemPriority": "high",
      },
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Describe the inputs",
            "partPriority": "normal",
          },
          {
            "type": "image_url",
            "image_url": { "url": "data:image/png;base64,aW1hZ2U=" },
          },
          { "type": "text", "text": "MoonBit" },
        ],
        "messagePriority": "normal",
      },
      {
        "role": "assistant",
        "content": null,
        "reasoning_content": "Check the city.",
        "tool_calls": [
          {
            "id": "call-1",
            "type": "function",
            "function": {
              "name": "lookup",
              "arguments": "{\"city\":\"Paris\"}",
            },
            "toolPriority": "critical",
            "extra_content": {
              "google": { "thought_signature": "signature-1" },
            },
          },
        ],
        "assistantPriority": "high",
      },
      {
        "role": "tool",
        "tool_call_id": "call-1",
        "content": "{\"temperature\":21}",
        "resultTier": "fresh",
      },
    ],
    "stream": true,
    "stream_options": { "include_usage": true },
    "user": "custom",
    "reasoning_effort": "high",
    "verbosity": "low",
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "lookup",
          "description": "Look up a city",
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
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "answer",
        "schema": { "type": "object" },
        "strict": true,
      },
    },
    "vendorFlag": true,
  })
  assert_eq(prepared.metadata_key, "localTest")
  assert_eq(prepared.warnings.length(), 3)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_true(
    prepared.warnings[1]
    is @provider.Unsupported(feature="frequencyPenalty", ..),
  )
  assert_true(
    prepared.warnings[2]
    is @provider.Unsupported(
      feature="provider-defined tool provider.search",
      ..
    ),
  )
}

///|
test "native V4 converter rejects provider-reference files" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptFile(
          data=@provider.V4FileReference(
            @provider.ProviderReference::single(
              provider="openaiCompatible",
              id="file-1",
            ),
          ),
          media_type="application/pdf",
          filename=Some("report.pdf"),
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  try
    default_openai_compatible_v4_prompt_converter(prompt, "local.chat")
  catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_eq(functionality, "file parts with provider references")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a provider-reference error")
  }
}

///|
test "compatible options merge raw and camel-case provider namespaces" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    provider_options={
      "test-provider": { "rawOnly": true, "shared": "raw" },
      "testProvider": { "camelOnly": true, "shared": "camel" },
    },
  )
  let prepared = prepare_compatible_v4_chat_request(
    "test-model", options, false, false, "test-provider.chat", false, false, true,
    default_openai_compatible_v4_prompt_converter,
  )
  json_inspect(prepared.body, content={
    "model": "test-model",
    "messages": [{ "role": "user", "content": "hello" }],
    "rawOnly": true,
    "shared": "camel",
    "camelOnly": true,
  })
  assert_eq(prepared.metadata_key, "testProvider")
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Deprecated(
        setting="providerOptions key 'test-provider'",
        message="Use 'testProvider' instead."
      )
    }),
  )
}

///|
test "compatible deprecated generic namespace uses AI SDK warning text" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    provider_options={ "openai-compatible": { "user": "legacy-user" } },
  )
  let prepared = prepare_compatible_v4_chat_request(
    "test-model", options, false, false, "test-provider.chat", false, false, true,
    default_openai_compatible_v4_prompt_converter,
  )
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Deprecated(
        setting="providerOptions key 'openai-compatible'",
        message="Use 'openaiCompatible' instead."
      )
    }),
  )
}

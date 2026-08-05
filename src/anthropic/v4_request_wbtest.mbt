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
        @provider.V4PromptReasoning(text="I will inspect the first page.", provider_options={
          "anthropic.messages": { "signature": "sig-v4" },
        }),
        @provider.V4PromptText(text="Reading now.", provider_options=Map([])),
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
    tools=[
      @provider.ToolDefinition::new("inspect_pdf", {
        "type": "object",
        "properties": { "page": { "type": "integer" } },
      }),
    ],
    tool_choice=@provider.Named("inspect_pdf"),
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
            "content": [{ "type": "text", "text": "{\"title\":\"MoonBit\"}" }],
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

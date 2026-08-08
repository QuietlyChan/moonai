///|
test "OpenAI Responses V4 preserves native prompt and request values" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(
      content="Answer from the supplied inputs.",
      provider_options=Map([]),
    ),
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptText(
          text="Inspect both files",
          provider_options=Map([]),
        ),
        @provider.V4PromptFile(
          data=@provider.V4FileBytes(b"image"),
          media_type="image/png",
          filename=None,
          provider_options={ "openai": { "imageDetail": "high" } },
        ),
        @provider.V4PromptFile(
          data=@provider.V4FileBytes(b"PDF"),
          media_type="application/pdf",
          filename=Some("report.pdf"),
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptReasoning(text="I should look up the record.", provider_options={
          "openai": {
            "itemId": "rs_1",
            "reasoningEncryptedContent": "encrypted-1",
          },
        }),
        @provider.V4PromptText(text="Looking it up.", provider_options={
          "openai": { "phase": "commentary" },
        }),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="call_1",
            tool_name="lookup",
            input={ "city": "Hangzhou", "units": "celsius" },
            provider_options={
              "openai": {
                "caller": { "type": "program", "callerId": "program_1" },
              },
            },
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
            value={ "temperature": 23 },
          ),
        ),
        @provider.V4PromptToolApprovalResponse(
          @provider.LanguageModelV4ToolApprovalResponsePart::new(
            approval_id="approval_1",
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
          "properties": {
            "city": { "type": "string" },
            "units": { "type": "string" },
          },
          "required": ["city"],
        },
        description="Look up a city",
        strict=true,
      ),
      @provider.LanguageModelV4Tool::provider(
        id="openai.web_search",
        name="web_search",
      ),
    ],
    tool_choice=@provider.V4ToolChoiceTool("lookup"),
    response_format=@provider.LanguageModelV4ResponseFormat::json(
      name="answer",
      schema={ "type": "object" },
    ),
    provider_options={
      "openai": {
        "store": false,
        "parallelToolCalls": true,
        "metadata": { "request": "v4" },
        "textVerbosity": "low",
      },
    },
  )
  let prepared = prepare_openai_v4_responses_request(
    "gpt-4o", options, "openai.responses", false,
  )
  assert_eq(prepared.warnings, [])
  json_inspect(prepared.body, content={
    "model": "gpt-4o",
    "input": [
      { "role": "system", "content": "Answer from the supplied inputs." },
      {
        "role": "user",
        "content": [
          { "type": "input_text", "text": "Inspect both files" },
          {
            "type": "input_image",
            "image_url": "data:image/png;base64,aW1hZ2U=",
            "detail": "high",
          },
          {
            "type": "input_file",
            "filename": "report.pdf",
            "file_data": "data:application/pdf;base64,UERG",
          },
        ],
      },
      {
        "type": "reasoning",
        "id": "rs_1",
        "summary": [
          { "type": "summary_text", "text": "I should look up the record." },
        ],
        "encrypted_content": "encrypted-1",
      },
      {
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "Looking it up." }],
        "phase": "commentary",
      },
      {
        "type": "function_call",
        "call_id": "call_1",
        "name": "lookup",
        "arguments": "{\"city\":\"Hangzhou\",\"units\":\"celsius\"}",
        "caller": { "type": "program", "caller_id": "program_1" },
      },
      {
        "type": "function_call_output",
        "call_id": "call_1",
        "output": "{\"temperature\":23}",
      },
      {
        "type": "mcp_approval_response",
        "approval_request_id": "approval_1",
        "approve": true,
      },
    ],
    "text": {
      "format": {
        "type": "json_schema",
        "name": "answer",
        "schema": { "type": "object" },
        "strict": true,
      },
      "verbosity": "low",
    },
    "metadata": { "request": "v4" },
    "parallel_tool_calls": true,
    "store": false,
    "include": ["web_search_call.action.sources"],
    "tools": [
      {
        "type": "function",
        "name": "lookup",
        "description": "Look up a city",
        "parameters": {
          "type": "object",
          "properties": {
            "city": { "type": "string" },
            "units": { "type": "string" },
          },
          "required": ["city"],
        },
        "strict": true,
      },
      { "type": "web_search" },
    ],
    "tool_choice": { "type": "function", "name": "lookup" },
  })
}

///|
test "OpenAI Responses V4 replays reasoning without legacy lowering" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptReasoning(text="first", provider_options={
          "openai": { "itemId": "rs_v4" },
        }),
        @provider.V4PromptReasoning(text="second", provider_options={
          "openai": {
            "itemId": "rs_v4",
            "reasoningEncryptedContent": "ciphertext",
          },
        }),
        @provider.V4PromptText(text="answer", provider_options=Map([])),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_openai_v4_responses_request(
    "o1",
    @provider.LanguageModelV4CallOptions::new(
      prompt,
      reasoning=@provider.V4ReasoningHigh,
      provider_options={ "openai": { "store": false } },
    ),
    "openai.responses",
    false,
  )
  assert_eq(prepared.warnings, [])
  json_inspect(prepared.body, content={
    "model": "o1",
    "input": [
      {
        "type": "reasoning",
        "id": "rs_v4",
        "summary": [
          { "type": "summary_text", "text": "first" },
          { "type": "summary_text", "text": "second" },
        ],
        "encrypted_content": "ciphertext",
      },
      {
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "answer" }],
      },
    ],
    "store": false,
    "include": ["reasoning.encrypted_content"],
    "reasoning": { "effort": "high", "summary": "detailed" },
  })
}

///|
test "OpenAI Responses V4 skips items from a previous response" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptText(text="old answer", provider_options={
          "openai": { "itemId": "msg_1" },
        }),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="call_1",
            tool_name="lookup",
            input={ "city": "Paris" },
            provider_options={ "openai": { "itemId": "fc_1" } },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_openai_v4_responses_request(
    "gpt-4o",
    @provider.LanguageModelV4CallOptions::new(
      prompt,
      tools=[
        @provider.LanguageModelV4Tool::function("lookup", { "type": "object" }),
      ],
      provider_options={ "openai": { "previousResponseId": "resp_1" } },
    ),
    "openai.responses",
    false,
  )
  assert_eq(prepared.warnings, [])
  json_inspect(prepared.body, content={
    "model": "gpt-4o",
    "input": [],
    "previous_response_id": "resp_1",
    "tools": [
      {
        "type": "function",
        "name": "lookup",
        "parameters": { "type": "object" },
      },
    ],
  })
}

///|
test "OpenAI Responses V4 maps hosted tools and execution mode" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="search_call_1",
            tool_name="tool_search",
            input={
              "call_id": "search_call_1",
              "arguments": { "goal": "weather" },
            },
            provider_options={ "openai": { "itemId": "search_item_1" } },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4ToolMessage(
      content=[
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="search_call_1",
            tool_name="tool_search",
            value={
              "tools": [
                {
                  "type": "function",
                  "name": "weather",
                  "parameters": { "type": "object" },
                },
              ],
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_openai_v4_responses_request(
    "gpt-5",
    @provider.LanguageModelV4CallOptions::new(
      prompt,
      tools=[
        @provider.LanguageModelV4Tool::provider(
          id="openai.tool_search",
          name="tool_search",
          args={ "execution": "client" },
        ),
        @provider.LanguageModelV4Tool::provider(
          id="openai.shell",
          name="shell",
          args={ "environment": { "type": "containerAuto" } },
        ),
      ],
      provider_options={ "openai": { "store": false } },
    ),
    "openai.responses",
    false,
  )
  assert_eq(prepared.warnings, [])
  assert_eq(prepared.shell_provider_executed, true)
  json_inspect(prepared.body, content={
    "model": "gpt-5",
    "input": [
      {
        "type": "tool_search_call",
        "id": "search_item_1",
        "execution": "client",
        "call_id": "search_call_1",
        "status": "completed",
        "arguments": { "goal": "weather" },
      },
      {
        "type": "tool_search_output",
        "execution": "client",
        "call_id": "search_call_1",
        "status": "completed",
        "tools": [
          {
            "type": "function",
            "name": "weather",
            "parameters": { "type": "object" },
          },
        ],
      },
    ],
    "store": false,
    "include": ["reasoning.encrypted_content"],
    "tools": [
      { "type": "tool_search", "execution": "client" },
      { "type": "shell", "environment": { "type": "container_auto" } },
    ],
  })
}

///|
test "OpenAI Responses V4 restores MCP approval call IDs from prompt metadata" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="pending-call-1",
            tool_name="mcp.create_short_url",
            input={ "url": "https://ai-sdk.dev" },
            provider_executed=true,
            provider_options={
              "openai": { "approvalRequestId": "approval-request-1" },
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  assert_eq(
    openai_responses_approval_tool_call_ids(prompt, "openai.responses"),
    Map([("approval-request-1", "pending-call-1")]),
  )
}

///|
test "OpenAI Responses V4 sends an MCP denial only as an approval response" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="pending-call-1",
            tool_name="mcp.create_short_url",
            input={ "url": "https://ai-sdk.dev" },
            provider_executed=true,
            provider_options={
              "openai": { "approvalRequestId": "approval-request-1" },
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4ToolMessage(
      content=[
        @provider.V4PromptToolApprovalResponse(
          @provider.LanguageModelV4ToolApprovalResponsePart::new(
            approval_id="approval-request-1",
            approved=false,
            reason="policy denied",
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::execution_denied(
            tool_call_id="pending-call-1",
            tool_name="mcp.create_short_url",
            reason="policy denied",
            provider_options={
              "openai": { "approvalId": "approval-request-1" },
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_openai_v4_responses_request(
    "gpt-5",
    @provider.LanguageModelV4CallOptions::new(prompt),
    "openai.responses",
    false,
  )
  assert_eq(prepared.warnings, [])
  json_inspect(prepared.body, content={
    "model": "gpt-5",
    "input": [
      { "type": "item_reference", "id": "approval-request-1" },
      {
        "type": "mcp_approval_response",
        "approval_request_id": "approval-request-1",
        "approve": false,
      },
    ],
  })
}

///|
test "OpenAI Responses V4 retains the selected web search tool name" {
  let prepared = prepare_openai_v4_responses_request(
    "gpt-5",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([]),
      tools=[
        @provider.LanguageModelV4Tool::provider(
          id="openai.web_search_preview",
          name="preview-search",
        ),
      ],
    ),
    "openai.responses",
    false,
  )
  assert_eq(prepared.web_search_tool_name, Some("preview-search"))
}

///|
test "OpenAI Responses V4 uses the Azure prompt options namespace" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptFile(
          data=@provider.V4FileBytes(b"image"),
          media_type="image/png",
          filename=None,
          provider_options={
            "azure": {
              "imageDetail": "high",
              "promptCacheBreakpoint": { "mode": "explicit" },
            },
          },
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="call-azure",
            tool_name="lookup",
            input={ "city": "Seattle" },
            provider_options={
              "azure": {
                "namespace": "travel",
                "caller": { "type": "program", "callerId": "program-1" },
              },
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_openai_v4_responses_request(
    "gpt-4o",
    @provider.LanguageModelV4CallOptions::new(
      prompt,
      tools=[
        @provider.LanguageModelV4Tool::function("lookup", {
          "type": "object",
          "properties": Json::empty_object(),
        }),
      ],
      provider_options={ "azure": { "store": false } },
    ),
    "azure.responses",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "gpt-4o",
    "input": [
      {
        "role": "user",
        "content": [
          {
            "type": "input_image",
            "image_url": "data:image/png;base64,aW1hZ2U=",
            "detail": "high",
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
        ],
      },
      {
        "type": "function_call",
        "call_id": "call-azure",
        "name": "lookup",
        "arguments": "{\"city\":\"Seattle\"}",
        "namespace": "travel",
        "caller": { "type": "program", "caller_id": "program-1" },
      },
    ],
    "store": false,
    "tools": [
      {
        "type": "function",
        "name": "lookup",
        "parameters": { "type": "object", "properties": Json::empty_object() },
      },
    ],
  })
}

///|
test "OpenAI Responses V4 ignores arbitrary provider option namespaces" {
  let prepared = prepare_openai_v4_responses_request(
    "gpt-4o",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([]),
      provider_options={
        "gateway": { "store": false },
        "openai": { "store": true },
      },
    ),
    "gateway.responses",
    false,
  )
  json_inspect(prepared.body, content={
    "model": "gpt-4o",
    "input": [],
    "store": true,
  })
}

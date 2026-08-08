///|
test "high-level advisor tool exposes typed factory semantics" {
  let tool = advisor_20260301(
    model="claude-opus-4-8",
    max_uses=2,
    caching=AnthropicAdvisorCaching::new(ttl=AnthropicCacheFiveMinutes),
  )
  assert_true(tool.is_provider_executed())
  assert_true(tool.supports_deferred_results())
  assert_true(
    @provider_utils.json_schema_matches(
      tool.input_schema().unwrap(),
      Json::empty_object(),
    ),
  )
  assert_true(
    !@provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
      "unexpected": true,
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(tool.output_schema().unwrap(), {
      "type": "advisor_result",
      "text": "Use the smaller plan.",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(tool.output_schema().unwrap(), {
      "type": "advisor_redacted_result",
      "encryptedContent": "ciphertext",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(tool.output_schema().unwrap(), {
      "type": "advisor_tool_result_error",
      "errorCode": "unavailable",
    }),
  )
  match tool.to_tool_definition("strategist") {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "anthropic.advisor_20260301")
      assert_eq(name, "strategist")
      assert_eq(args, {
        "model": "claude-opus-4-8",
        "maxUses": 2,
        "caching": { "type": "ephemeral", "ttl": "5m" },
      })
    }
    _ => fail("expected advisor provider tool")
  }
}

///|
test "high-level advisor tool only requires a model" {
  let tool = advisor_20260301(model="claude-sonnet-4-6")
  match tool.to_tool_definition("advisor") {
    @provider.ProviderTool(args~, ..) =>
      assert_eq(args, { "model": "claude-sonnet-4-6" })
    _ => fail("expected advisor provider tool")
  }
}

///|
async test "high-level advisor tool forwards input lifecycle callbacks" {
  let events : Array[String] = []
  let tool = advisor_20260301(
    model="claude-sonnet-4-6",
    on_input_start=_options => events.push("start"),
    on_input_delta=options => events.push("delta:" + options.input_text_delta),
    on_input_available=options => {
      events.push("available:" + options.input.stringify())
    },
  )
  tool.invoke_input_start(
    @provider_utils.ToolExecutionOptions::new(tool_call_id="advisor-1"),
  )
  tool.invoke_input_delta(
    @provider_utils.ToolInputDeltaOptions::new(
      input_text_delta="{}",
      tool_call_id="advisor-1",
    ),
  )
  tool.invoke_input_available(
    @provider_utils.ToolInputAvailableOptions::new(
      input=Json::empty_object(),
      tool_call_id="advisor-1",
    ),
  )
  assert_eq(events, ["start", "delta:{}", "available:{}"])
}

///|
test "Anthropic V4 replays all advisor result variants with a custom tool name" {
  let tool = advisor_20260301(model="claude-opus-4-8")
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="advisor-plain",
            tool_name="strategist",
            input=Json::empty_object(),
            provider_executed=true,
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="advisor-plain",
            tool_name="strategist",
            value={
              "type": "advisor_result",
              "text": "Prefer the bounded implementation.",
            },
          ),
        ),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="advisor-redacted",
            tool_name="strategist",
            input=Json::empty_object(),
            provider_executed=true,
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::json(
            tool_call_id="advisor-redacted",
            tool_name="strategist",
            value={
              "type": "advisor_redacted_result",
              "encryptedContent": "ciphertext",
            },
          ),
        ),
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="advisor-error",
            tool_name="strategist",
            input=Json::empty_object(),
            provider_executed=true,
          ),
        ),
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::error_json(
            tool_call_id="advisor-error",
            tool_name="strategist",
            value={
              "type": "advisor_tool_result_error",
              "errorCode": "unavailable",
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(prompt, tools=[
      @provider.LanguageModelV4Tool::from_tool_definition(
        tool.to_tool_definition("strategist"),
      ),
    ]),
    "anthropic.messages",
    false,
  )
  assert_true(
    prepared.body
    is {
      "messages": [
        {
          "role": "assistant",
          "content": [
            {
              "type": "server_tool_use",
              "id": "advisor-plain",
              "name": "advisor",
              "input": Object(_),
              ..
            },
            {
              "type": "advisor_tool_result",
              "tool_use_id": "advisor-plain",
              "content": {
                "type": "advisor_result",
                "text": "Prefer the bounded implementation.",
                ..
              },
              ..
            },
            {
              "type": "server_tool_use",
              "id": "advisor-redacted",
              "name": "advisor",
              "input": Object(_),
              ..
            },
            {
              "type": "advisor_tool_result",
              "tool_use_id": "advisor-redacted",
              "content": {
                "type": "advisor_redacted_result",
                "encrypted_content": "ciphertext",
                ..
              },
              ..
            },
            {
              "type": "server_tool_use",
              "id": "advisor-error",
              "name": "advisor",
              "input": Object(_),
              ..
            },
            {
              "type": "advisor_tool_result",
              "tool_use_id": "advisor-error",
              "content": {
                "type": "advisor_tool_result_error",
                "error_code": "unavailable",
                ..
              },
              ..
            },
          ],
          ..
        },
      ],
      "tools": [
        {
          "type": "advisor_20260301",
          "name": "advisor",
          "model": "claude-opus-4-8",
          ..
        },
      ],
      ..
    },
  )
  assert_true(prepared.beta_features.contains("advisor-tool-2026-03-01"))
  assert_eq(prepared.warnings.length(), 0)
}

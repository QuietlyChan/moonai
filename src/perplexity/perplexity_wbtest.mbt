///|
fn perplexity_test_prompt(text : String) -> @provider.LanguageModelV4Prompt {
  @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[@provider.V4PromptText(text~, provider_options=Map([]))],
      provider_options=Map([]),
    ),
  ])
}

///|
fn perplexity_test_model(model_id : String) -> PerplexityLanguageModel {
  perplexity_chat_value(
    model_id,
    api_key="test-key",
    base_url="https://api.perplexity.ai",
    headers=Map([]),
    idle_timeout_ms=120_000,
    http_transport=@provider_utils.native_http_transport(),
    id_generator=() => "generated-id",
  )
}

///|
test "Perplexity Agent model selection uses presets only for documented IDs" {
  let preset = perplexity_test_model("fast").prepare_agent_request(
    @provider.LanguageModelV4CallOptions::new(perplexity_test_prompt("hello")),
  )
  assert_true(preset.body is { "preset": "fast", .. })
  assert_false(preset.body is { "model": _, .. })

  let custom = perplexity_test_model("sonar-pro").prepare_agent_request(
    @provider.LanguageModelV4CallOptions::new(perplexity_test_prompt("hello")),
  )
  assert_true(custom.body is { "model": "sonar-pro", .. })
  assert_false(custom.body is { "preset": _, .. })
}

///|
test "Perplexity Agent request maps prompts options and native tools" {
  let options = @provider.LanguageModelV4CallOptions::new(
    perplexity_test_prompt("Find a source"),
    max_output_tokens=256,
    temperature=0.3,
    reasoning=@provider.V4ReasoningHigh,
    provider_options={
      "perplexity": {
        "tools": [{ "type": "web_search", "max_results": 4 }],
        "max_steps": 2,
        "language_preference": "en",
      },
    },
  )
  let prepared = perplexity_test_model("sonar").prepare_agent_request(options)
  assert_eq(options.provider_options.length(), 1)
  assert_eq(
    @provider_utils.resolve_provider_options(
      options.provider_options,
      provider_name="perplexity",
    ).values.length(),
    3,
  )
  assert_true(prepared.body is { "max_steps": 2, .. })
  assert_true(prepared.body is { "language_preference": "en", .. })
  assert_true(prepared.body is { "reasoning": { "effort": "high", .. }, .. })
  assert_true(prepared.body is { "tools": [{ "type": "web_search", .. }], .. })
  assert_true(prepared.body is { "max_output_tokens": 256, .. })
  assert_eq(prepared.warnings.length(), 0)
}

///|
test "Perplexity Agent none tool choice disables native and function tools" {
  let options = @provider.LanguageModelV4CallOptions::new(
    perplexity_test_prompt("hello"),
    tools=[
      @provider.LanguageModelV4Tool::function("lookup", {
        "type": "object",
        "properties": { "q": { "type": "string" } },
      }),
    ],
    tool_choice=@provider.V4ToolChoiceNone,
    provider_options={ "perplexity": { "tools": [{ "type": "web_search" }] } },
  )
  let prepared = perplexity_test_model("sonar").prepare_agent_request(options)
  assert_true(prepared.body is { "max_tool_calls": 0, .. })
  match prepared.body {
    Object(fields) => assert_false(fields.contains("tools"))
    _ => fail("expected an Agent API request object")
  }
}

///|
test "Perplexity Agent function tools and JSON schema use native wire shapes" {
  let options = @provider.LanguageModelV4CallOptions::new(
    perplexity_test_prompt("lookup"),
    tools=[
      @provider.LanguageModelV4Tool::function(
        "lookup",
        { "type": "object", "properties": { "q": { "type": "string" } } },
        description="Look something up",
        strict=true,
      ),
    ],
    response_format=@provider.LanguageModelV4ResponseFormat::json(
      schema={ "type": "object" },
      name="answer",
    ),
  )
  assert_eq(options.tools.length(), 1)
  assert_true(options.response_format is @provider.V4ResponseJson(_))
  let prepared = perplexity_test_model("sonar").prepare_agent_request(options)
  assert_true(prepared.body is { "tools": [{ "name": "lookup", .. }], .. })
  assert_true(
    prepared.body is { "response_format": { "type": "json_schema", .. }, .. },
  )
  assert_false(
    prepared.body
    is {
      "response_format": { "json_schema": { "description": _, .. }, .. },
      ..
    },
  )
}

///|
test "Perplexity Agent prompt accepts image URLs and rejects unsupported files" {
  let image_prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptFile(
          data=@provider.V4FileUrl("https://example.com/image.png"),
          media_type="image/png",
          filename=None,
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let (input, _) = perplexity_agent_prompt_input(image_prompt)
  assert_true(
    input[0]
    is {
      "content": [
        {
          "type": "input_image",
          "image_url": "https://example.com/image.png",
          ..
        },
      ],
      ..
    },
  )

  let file_prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4UserMessage(
      content=[
        @provider.V4PromptFile(
          data=@provider.V4FileUrl("https://example.com/document.pdf"),
          media_type="application/pdf",
          filename=None,
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  try perplexity_agent_prompt_input(file_prompt) catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_true(functionality.contains("application/pdf"))
    error => fail("unexpected Perplexity file error: \{error}")
  } noraise {
    _ => fail("expected unsupported file to be rejected")
  }
}

///|
test "Perplexity Agent prompt round-trips tool calls results and signatures" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4AssistantMessage(
      content=[
        @provider.V4PromptToolCall(
          @provider.LanguageModelV4ToolCallPart::new(
            tool_call_id="call-1",
            tool_name="lookup",
            input={ "q": "moon" },
            provider_options={
              "perplexity": { "thoughtSignature": "signature" },
            },
          ),
        ),
      ],
      provider_options=Map([]),
    ),
    @provider.V4ToolMessage(
      content=[
        @provider.V4PromptToolResult(
          @provider.LanguageModelV4ToolResultPart::text(
            tool_call_id="call-1",
            tool_name="lookup",
            value="found",
          ),
        ),
      ],
      provider_options=Map([]),
    ),
  ])
  let (input, warnings) = perplexity_agent_prompt_input(prompt)
  assert_eq(warnings.length(), 0)
  assert_true(
    input[0]
    is {
      "type": "function_call",
      "call_id": "call-1",
      "arguments": "{\"q\":\"moon\"}",
      "thought_signature": "signature",
      ..
    },
  )
  assert_true(
    input[1]
    is {
      "type": "function_call_output",
      "call_id": "call-1",
      "output": "found",
      ..
    },
  )
}

///|
test "Perplexity Agent validation rejects malformed handled items but accepts native traces" {
  assert_eq(
    perplexity_agent_output_item_validation_error({
      "type": "finance_results",
      "results": { "stocks": ["MOON"] },
    }),
    None,
  )
  assert_true(
    perplexity_agent_output_item_validation_error({
      "type": "search_results",
      "results": [{ "url": 12 }],
    })
    is Some(_),
  )
  let decoder = PerplexityAgentStreamDecoder::new(true, () => "generated-id")
  let _ = decoder.feed_line("data: {\"delta\":42}")
  let malformed = decoder.feed_line("")
  assert_true(malformed.events[0] is @provider.V4Raw(_))
  assert_true(malformed.events[1] is @provider.V4Error(_))
}

///|
test "Perplexity Agent maps finish reasons errors and empty usage" {
  assert_eq(
    perplexity_map_agent_finish_reason(
      "incomplete",
      Some("max_output_tokens"),
      false,
    ).unified,
    @provider.V4FinishLength,
  )
  assert_eq(
    perplexity_map_agent_finish_reason(
      "incomplete",
      Some("content_filter"),
      false,
    ).unified,
    @provider.V4FinishContentFilter,
  )
  assert_eq(
    perplexity_map_agent_finish_reason("failed", None, false).unified,
    @provider.V4FinishError,
  )
  assert_eq(perplexity_agent_usage(None).input_tokens.total, None)
  assert_eq(perplexity_error_to_message({ "error": "busy" }), Some("busy"))
  assert_eq(
    perplexity_error_to_message({ "detail": [{ "msg": "invalid model" }] }),
    Some("invalid model"),
  )
  let metadata = perplexity_agent_provider_metadata(
    Some({ "tool_calls_details": { "fetch_url": { "invocation": 1 } } }),
    [],
  )
  assert_true(
    metadata
    is { "perplexity": { "usage": { "numSearchQueries": 0, .. }, .. }, .. },
  )
}

///|
test "Perplexity Agent response preserves text, deduplicates sources and maps usage" {
  let decoded = perplexity_agent_decoded_response(
    {
      "id": "resp-1",
      "created_at": 1727000000,
      "model": "sonar",
      "status": "completed",
      "output": [
        {
          "type": "message",
          "content": [
            {
              "type": "output_text",
              "text": "Answer",
              "annotations": [
                {
                  "type": "url_citation",
                  "url": "https://example.com",
                  "title": "Example",
                },
              ],
            },
          ],
        },
        {
          "type": "search_results",
          "queries": ["example", "example"],
          "results": [
            {
              "id": 7,
              "title": "Example source",
              "url": "https://example.com",
              "snippet": "A source",
            },
          ],
        },
        {
          "type": "fetch_url_results",
          "contents": [
            {
              "title": "Fetched source",
              "url": "https://example.com",
              "snippet": "Fetched snippet",
            },
          ],
        },
        { "type": "finance_results", "results": [{ "symbol": "MOON" }] },
      ],
      "usage": {
        "input_tokens": 10,
        "output_tokens": 5,
        "input_tokens_details": {
          "cached_tokens": 2,
          "cache_creation_input_tokens": 1,
        },
        "output_tokens_details": { "reasoning_tokens": 2 },
        "tool_calls_details": { "search_web": { "invocation": 3 } },
        "cost": { "input_cost": 0.01, "total_cost": 0.02, "currency": "USD" },
      },
    },
    () => "generated-id",
  )

  assert_eq(decoded.content.length(), 2)
  assert_true(
    decoded.content[0] is @provider.V4TextOutput({ text: "Answer", .. }),
  )
  assert_true(
    decoded.content[1]
    is @provider.V4SourceOutput(
      @provider.V4UrlSource(id="7", title=Some("Example source"), ..)
    ),
  )
  assert_eq(decoded.finish_reason.unified, @provider.V4FinishStop)
  assert_eq(decoded.response.unwrap().id, Some("resp-1"))
  assert_eq(decoded.usage.input_tokens.total, Some(10))
  assert_eq(decoded.usage.input_tokens.no_cache, Some(7))
  assert_eq(decoded.usage.input_tokens.cache_read, Some(2))
  assert_eq(decoded.usage.output_tokens.reasoning, Some(2))
  assert_true(
    decoded.provider_metadata
    is { "perplexity": { "searchQueries": ["example"], .. }, .. },
  )
  assert_true(
    decoded.provider_metadata
    is { "perplexity": { "usage": { "numSearchQueries": 3, .. }, .. }, .. },
  )
}

///|
test "Perplexity Agent function calls determine tool-call finish reason" {
  let decoded = perplexity_agent_decoded_response(
    {
      "status": "requires_action",
      "output": [
        {
          "type": "function_call",
          "id": "item-1",
          "call_id": "call-1",
          "name": "lookup",
          "arguments": "{\"q\":\"moon\"}",
        },
      ],
    },
    () => "generated-id",
  )
  assert_eq(decoded.finish_reason.unified, @provider.V4FinishToolCalls)
  assert_true(
    decoded.content[0]
    is @provider.V4ToolCallOutput(
      {
        tool_call_id: "call-1",
        tool_name: "lookup",
        input: "{\"q\":\"moon\"}",
        ..
      }
    ),
  )
}

///|
test "Perplexity Agent response rejects failed and malformed payloads" {
  try
    perplexity_agent_decoded_response(
      {
        "status": "failed",
        "error": { "message": "request failed" },
        "output": [],
      },
      () => "generated-id",
    )
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_eq(message, "request failed")
      assert_true(data is { "status": "failed", .. })
    }
    error => fail("unexpected Agent API failure: \{error}")
  } noraise {
    _ => fail("expected failed Agent response to be rejected")
  }

  try
    perplexity_agent_decoded_response({ "status": "completed" }, () => "id")
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("output array"))
    error => fail("unexpected malformed Agent response: \{error}")
  } noraise {
    _ => fail("expected missing output to be rejected")
  }
}

///|
test "Perplexity Agent stream emits text metadata sources and final usage" {
  assert_eq(perplexity_agent_text_id(Some("msg-1"), None, Some(2)), "msg-1:2")
  assert_eq(perplexity_agent_text_id(None, Some(3), None), "3")
  let decoder = PerplexityAgentStreamDecoder::new(true, () => "generated-id")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg-1\",\"delta\":\"Hel\"}",
  )
  let delta = decoder.feed_line("")
  assert_true(delta.events[0] is @provider.V4Raw(_))
  assert_true(delta.events[1] is @provider.V4TextStart(id="msg-1", ..))
  assert_true(
    delta.events[2] is @provider.V4TextDelta(id="msg-1", delta="Hel", ..),
  )

  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-1\",\"created_at\":1727000000,\"model\":\"fast\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"id\":\"msg-1\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\",\"annotations\":[{\"url\":\"https://example.com\",\"title\":\"Example\"}]}]},{\"type\":\"search_results\",\"queries\":[\"example\"],\"results\":[{\"id\":1,\"title\":\"Example\",\"url\":\"https://example.com\"}]}],\"usage\":{\"input_tokens\":2,\"output_tokens\":1}}}",
  )
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_true(
    terminal.events.any(event => {
      event is @provider.V4TextDelta(id="msg-1", delta="lo", ..)
    }),
  )
  assert_true(
    terminal.events.any(event => event is @provider.V4TextEnd(id="msg-1", ..)),
  )
  assert_true(
    terminal.events.any(event => {
      event is @provider.V4ResponseMetadataReady({ id: Some("resp-1"), .. })
    }),
  )
  assert_true(
    terminal.events.any(event => {
      event is @provider.V4SourceReady(@provider.V4UrlSource(id="1", ..))
    }),
  )
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishStop, raw: Some("completed"), },
        usage={ input_tokens: { total: Some(2), .. }, .. },
        ..
      )
    }),
  )
}

///|
test "Perplexity Agent stream emits reasoning and function-call events" {
  let decoder = PerplexityAgentStreamDecoder::new(false, () => "generated-id")
  let _ = decoder.feed_line(
    "data: {\"type\":\"response.reasoning.started\",\"sequence_number\":5,\"thought\":\"checking\"}",
  )
  let reasoning = decoder.feed_line("")
  assert_true(
    reasoning.events[0] is @provider.V4ReasoningStart(id="reasoning-5", ..),
  )
  assert_true(
    reasoning.events[1]
    is @provider.V4ReasoningDelta(id="reasoning-5", delta="checking", ..),
  )

  let _ = decoder.feed_line(
    "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"item-1\",\"call_id\":\"call-1\",\"name\":\"lookup\",\"arguments\":\"{\\\"q\\\":\\\"moon\\\"}\"}}",
  )
  let tool = decoder.feed_line("")
  assert_true(
    tool.events.any(event => {
      event is @provider.V4ToolInputStart(id="call-1", tool_name="lookup", ..)
    }),
  )
  assert_true(
    tool.events.any(event => {
      event is @provider.V4ToolInputDelta(id="call-1", ..)
    }),
  )
  assert_true(
    tool.events.any(event => event is @provider.V4ToolInputEnd(id="call-1", ..)),
  )
  assert_true(
    tool.events.any(event => {
      event is @provider.V4ToolCallReady({ tool_call_id: "call-1", .. })
    }),
  )

  let _ = decoder.feed_line(
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[{\"type\":\"function_call\",\"id\":\"item-1\",\"call_id\":\"call-1\",\"name\":\"lookup\",\"arguments\":\"{\\\"q\\\":\\\"moon\\\"}\"}]}}",
  )
  let terminal = decoder.feed_line("")
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishToolCalls, .. },
        ..
      )
    }),
  )
}

///|
test "Perplexity Agent stream reports malformed chunks and interrupted EOF" {
  let malformed = PerplexityAgentStreamDecoder::new(true, () => "generated-id")
  let _ = malformed.feed_line("data: {invalid")
  let error_batch = malformed.feed_line("")
  assert_true(error_batch.events[0] is @provider.V4Raw(_))
  assert_true(error_batch.events[1] is @provider.V4Error(_))
  let errored_finish = malformed.finish_stream()
  assert_true(
    errored_finish.events[0]
    is @provider.V4Finish(reason={ unified: @provider.V4FinishError, .. }, ..),
  )

  let interrupted = PerplexityAgentStreamDecoder::new(false, () => {
    "generated-id"
  }).finish_stream()
  assert_true(
    interrupted.events[0]
    is @provider.V4Finish(reason={ raw: Some("interrupted"), .. }, ..),
  )

  let done_without_response = PerplexityAgentStreamDecoder::new(false, () => {
    "generated-id"
  })
  let _ = done_without_response.feed_line("data: [DONE]")
  let done = done_without_response.feed_line("")
  assert_true(
    done.events[0]
    is @provider.V4Finish(reason={ raw: Some("interrupted"), .. }, ..),
  )
}

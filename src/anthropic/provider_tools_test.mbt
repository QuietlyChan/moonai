///|
fn assert_anthropic_high_level_tool(
  tool : @provider_utils.Tool,
  expected_id : String,
  expected_provider_executed : Bool,
) -> Unit raise {
  assert_eq(tool.is_provider_executed(), expected_provider_executed)
  match tool.to_tool_definition("visible_name") {
    @provider.ProviderTool(id~, name~, ..) => {
      assert_eq(id, expected_id)
      assert_eq(name, "visible_name")
    }
    _ => fail("expected an Anthropic provider tool")
  }
}

///|
test "Anthropic public factory exposes the AI SDK provider contract" {
  let provider = createAnthropic(
    api_key="test-key",
    base_url="https://example.test/v1",
  )
  let generic_provider = provider as &@provider.ProviderV4
  assert_eq(generic_provider.specification_version(), "v4")
  let language_model = generic_provider.language_model("claude-test")
  assert_eq(language_model.specification_version(), "v4")
  assert_eq(language_model.provider(), "anthropic.messages")
  assert_eq(language_model.model_id(), "claude-test")
  let files = generic_provider.files().unwrap()
  assert_eq(files.specification_version(), "v4")
  assert_eq(files.provider(), "anthropic.messages")
  let skills = generic_provider.skills().unwrap()
  assert_eq(skills.specification_version(), "v4")
  assert_eq(skills.provider(), "anthropic.skills")
  assert_true(generic_provider.reranking_model("missing") is None)
  assert_true(generic_provider.speech_model("missing") is None)
  assert_true(generic_provider.transcription_model("missing") is None)
  try generic_provider.embedding_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.EmbeddingModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected Anthropic embedding model rejection")
  }
  try generic_provider.image_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.ImageModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected Anthropic image model rejection")
  }
}

///|
test "Anthropic provider exposes the AI SDK languageModel alias" {
  let provider = createAnthropic(api_key="test-key")
  let snake_case = provider.language_model("claude-sonnet-4-6")
  let camel_case = provider.languageModel("claude-sonnet-4-6")
  assert_eq(snake_case.model_id(), "claude-sonnet-4-6")
  assert_eq(camel_case.model_id(), snake_case.model_id())
  assert_eq(camel_case.provider(), snake_case.provider())
}

///|
test "Anthropic provider exposes the complete AI SDK tools namespace" {
  let tools = createAnthropic(api_key="test-key").tools()
  let definitions : Array[(@provider_utils.Tool, String, Bool)] = [
    (
      tools.advisor_20260301(model="claude-opus-4-8"),
      "anthropic.advisor_20260301",
      true,
    ),
    (tools.bash_20241022(), "anthropic.bash_20241022", false),
    (tools.bash_20250124(), "anthropic.bash_20250124", false),
    (tools.codeExecution_20250522(), "anthropic.code_execution_20250522", true),
    (tools.codeExecution_20250825(), "anthropic.code_execution_20250825", true),
    (tools.codeExecution_20260120(), "anthropic.code_execution_20260120", true),
    (
      tools.computer_20241022(display_width_px=1280, display_height_px=720),
      "anthropic.computer_20241022",
      false,
    ),
    (
      tools.computer_20250124(display_width_px=1280, display_height_px=720),
      "anthropic.computer_20250124",
      false,
    ),
    (
      tools.computer_20251124(display_width_px=1280, display_height_px=720),
      "anthropic.computer_20251124",
      false,
    ),
    (tools.memory_20250818(), "anthropic.memory_20250818", false),
    (tools.textEditor_20241022(), "anthropic.text_editor_20241022", false),
    (tools.textEditor_20250124(), "anthropic.text_editor_20250124", false),
    (tools.textEditor_20250429(), "anthropic.text_editor_20250429", false),
    (tools.textEditor_20250728(), "anthropic.text_editor_20250728", false),
    (tools.webFetch_20250910(), "anthropic.web_fetch_20250910", true),
    (tools.webFetch_20260209(), "anthropic.web_fetch_20260209", true),
    (tools.webSearch_20250305(), "anthropic.web_search_20250305", true),
    (tools.webSearch_20260209(), "anthropic.web_search_20260209", true),
    (
      tools.toolSearchRegex_20251119(),
      "anthropic.tool_search_regex_20251119",
      true,
    ),
    (
      tools.toolSearchBm25_20251119(),
      "anthropic.tool_search_bm25_20251119",
      true,
    ),
  ]
  for definition in definitions {
    assert_anthropic_high_level_tool(definition.0, definition.1, definition.2)
  }
}

///|
test "Anthropic namespace wrappers retain args and deferred semantics" {
  let tools = anthropicTools()
  let selected = @provider_utils.tool_set([
    (
      "advisor",
      tools.advisor_20260301(
        model="claude-opus-4-8",
        max_uses=3,
        caching=AnthropicAdvisorCaching::new(ttl=AnthropicCacheOneHour),
      ),
    ),
    (
      "desktop",
      tools.computer_20251124(
        display_width_px=1440,
        display_height_px=900,
        display_number=1,
        enable_zoom=true,
      ),
    ),
    ("editor", tools.textEditor_20250728(max_characters=12000)),
    (
      "fetch",
      tools.webFetch_20260209(
        max_uses=4,
        allowed_domains=["moonbitlang.com"],
        citations=AnthropicWebFetchCitations::new(enabled=true),
        max_content_tokens=4096,
      ),
    ),
  ])
  let definitions = @provider_utils.tool_definitions(selected)
  assert_eq(definitions.length(), 4)
  match definitions[0] {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "anthropic.advisor_20260301")
      assert_eq(name, "advisor")
      assert_eq(args, {
        "model": "claude-opus-4-8",
        "maxUses": 3,
        "caching": { "type": "ephemeral", "ttl": "1h" },
      })
    }
    _ => fail("expected the advisor provider definition")
  }
  match definitions[1] {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "anthropic.computer_20251124")
      assert_eq(name, "desktop")
      assert_eq(args, {
        "displayWidthPx": 1440,
        "displayHeightPx": 900,
        "displayNumber": 1,
        "enableZoom": true,
      })
    }
    _ => fail("expected the computer provider definition")
  }
  match definitions[2] {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "anthropic.text_editor_20250728")
      assert_eq(name, "editor")
      assert_eq(args, { "maxCharacters": 12000 })
    }
    _ => fail("expected the text-editor provider definition")
  }
  match definitions[3] {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "anthropic.web_fetch_20260209")
      assert_eq(name, "fetch")
      assert_eq(args, {
        "maxUses": 4,
        "allowedDomains": ["moonbitlang.com"],
        "citations": { "enabled": true },
        "maxContentTokens": 4096,
      })
    }
    _ => fail("expected the web-fetch provider definition")
  }
  assert_true(selected["advisor"].supports_deferred_results())
  assert_true(selected["fetch"].supports_deferred_results())
  assert_true(!selected["desktop"].supports_deferred_results())
  assert_true(!tools.codeExecution_20250522().supports_deferred_results())
  assert_true(tools.codeExecution_20250825().supports_deferred_results())
  assert_true(tools.codeExecution_20260120().supports_deferred_results())
}

///|
test "Anthropic namespace preserves provider caller metadata" {
  let code = anthropic_tools().codeExecution_20260120()
  let caller = @provider_utils.experimental_get_tool_caller(code).unwrap()
  assert_true(caller.is_provider())
  assert_eq(
    caller
    .prepare_provider_options(Map([("anthropic", { "deferLoading": true })]))
    .get("anthropic"),
    Some({ "deferLoading": true, "allowedCallers": ["code_execution_20260120"] }),
  )
}

///|
async test "Anthropic namespace client tools preserve behavior callbacks" {
  let events : Array[String] = []
  let tool = anthropic_tools().bash_20250124(
    output_schema={
      "type": "object",
      "properties": { "stdout": { "type": "string" } },
      "required": ["stdout"],
    },
    execute=(input, options) => {
      assert_eq(options.tool_call_id, "bash_1")
      events.push("execute:" + input.stringify())
      { "stdout": "MoonBit" }
    },
    needs_approval=@provider_utils.ToolNeedsApproval::when((input, options) => {
      assert_eq(options.tool_call_id, "bash_1")
      input is { "command": "rm -rf build", .. }
    }),
    on_input_start=options => events.push("start:" + options.tool_call_id),
    on_input_delta=options => events.push("delta:" + options.input_text_delta),
    on_input_available=options => {
      events.push("available:" + options.tool_call_id)
    },
  )
  let input : Json = { "command": "rm -rf build" }
  let execution_options = @provider_utils.ToolExecutionOptions::new(
    tool_call_id="bash_1",
  )
  tool.invoke_input_start(execution_options)
  tool.invoke_input_delta(
    @provider_utils.ToolInputDeltaOptions::new(
      input_text_delta="rm",
      tool_call_id="bash_1",
    ),
  )
  tool.invoke_input_available(
    @provider_utils.ToolInputAvailableOptions::new(
      input~,
      tool_call_id="bash_1",
    ),
  )
  assert_eq(
    tool.resolve_needs_approval(
      input,
      @provider_utils.ToolNeedsApprovalOptions::new(tool_call_id="bash_1"),
    ),
    Some(true),
  )
  assert_eq(
    tool.execute(input, execution_options),
    Some({ "stdout": "MoonBit" }),
  )
  assert_eq(events, [
    "start:bash_1", "delta:rm", "available:bash_1", "execute:{\"command\":\"rm -rf build\"}",
  ])
}

///|
async test "Anthropic namespace provider tools preserve streaming callbacks" {
  let events : Array[String] = []
  let tool = anthropic_tools().webSearch_20260209(
    on_input_start=options => events.push("start:" + options.tool_call_id),
    on_input_delta=options => events.push("delta:" + options.input_text_delta),
    on_input_available=options => {
      events.push("available:" + options.input.stringify())
    },
  )
  tool.invoke_input_start(
    @provider_utils.ToolExecutionOptions::new(tool_call_id="search_1"),
  )
  tool.invoke_input_delta(
    @provider_utils.ToolInputDeltaOptions::new(
      input_text_delta="Moon",
      tool_call_id="search_1",
    ),
  )
  tool.invoke_input_available(
    @provider_utils.ToolInputAvailableOptions::new(
      input={ "query": "MoonBit" },
      tool_call_id="search_1",
    ),
  )
  assert_eq(events, [
    "start:search_1", "delta:Moon", "available:{\"query\":\"MoonBit\"}",
  ])
}

///|
fn assert_openai_high_level_tool(
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
    _ => fail("expected an OpenAI provider tool")
  }
}

///|
test "OpenAI provider exposes the complete AI SDK tools namespace" {
  let tools = createOpenAI(api_key="test-key").tools()
  let file_options = OpenAIFileSearchOptions::new(
    vector_store_ids=["vs_1"],
    max_num_results=4,
  )
  let mcp_options = OpenAIMCPOptions::new(
    server_label="docs",
    server_url="https://mcp.example.com",
  )
  let definitions : Array[(@provider_utils.Tool, String, Bool)] = [
    (tools.applyPatch(), "openai.apply_patch", false),
    (
      tools.customTool(
        options=OpenAICustomToolOptions::new(
          description="Return a constrained identifier",
          format=CustomGrammarFormat(
            syntax=CustomGrammarRegex,
            definition="[a-z]+",
          ),
        ),
      ),
      "openai.custom",
      false,
    ),
    (
      tools.codeInterpreter(
        container=OpenAICodeInterpreterContainer::auto(file_ids=["file_1"]),
      ),
      "openai.code_interpreter",
      true,
    ),
    (tools.computer(), "openai.computer", false),
    (tools.fileSearch(file_options), "openai.file_search", true),
    (tools.imageGeneration(), "openai.image_generation", true),
    (tools.localShell(), "openai.local_shell", false),
    (
      tools.shell(environment=OpenAIShellEnvironment::local_environment()),
      "openai.shell",
      false,
    ),
    (tools.webSearchPreview(), "openai.web_search_preview", true),
    (tools.webSearch(), "openai.web_search", true),
    (tools.mcp(mcp_options), "openai.mcp", true),
    (tools.programmaticToolCalling(), "openai.programmatic_tool_calling", true),
    (tools.toolSearch(), "openai.tool_search", false),
  ]
  for definition in definitions {
    assert_openai_high_level_tool(definition.0, definition.1, definition.2)
  }
  assert_true(tools.programmaticToolCalling().supports_deferred_results())
  for definition in definitions {
    if definition.1 != "openai.programmatic_tool_calling" {
      assert_true(!definition.0.supports_deferred_results())
    }
  }
}

///|
test "OpenAI namespace tools retain typed arguments through tool sets" {
  let tools = createOpenAI(api_key="test-key").tools()
  let file_options = OpenAIFileSearchOptions::new(
    vector_store_ids=["vs_docs"],
    max_num_results=6,
    ranking=OpenAIFileSearchRanking::new(ranker="auto", score_threshold=0.75),
  )
  let shell_environment = OpenAIShellEnvironment::container_reference("ctr_1")
  let tool_set = @provider_utils.toolSet([
    ("docs", tools.fileSearch(file_options)),
    ("terminal", tools.shell(environment=shell_environment)),
  ])
  let definitions = @provider_utils.tool_definitions(tool_set)
  assert_eq(definitions.length(), 2)
  match definitions[0] {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "openai.file_search")
      assert_eq(name, "docs")
      assert_eq(args, {
        "vectorStoreIds": ["vs_docs"],
        "maxNumResults": 6,
        "ranking": { "ranker": "auto", "scoreThreshold": 0.75 },
      })
    }
    _ => fail("expected the file-search provider definition")
  }
  match definitions[1] {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "openai.shell")
      assert_eq(name, "terminal")
      assert_eq(args, {
        "environment": { "type": "containerReference", "containerId": "ctr_1" },
      })
    }
    _ => fail("expected the shell provider definition")
  }
}

///|
test "OpenAI high-level tools carry AI SDK input and output schemas" {
  let tools = createOpenAI(api_key="test-key").tools()
  let patch = tools.apply_patch()
  assert_true(
    @provider_utils.json_schema_matches(patch.input_schema().unwrap(), {
      "callId": "patch_1",
      "operation": {
        "type": "update_file",
        "path": "src/main.mbt",
        "diff": "@@ -1 +1 @@",
      },
    }),
  )
  assert_true(
    !@provider_utils.json_schema_matches(patch.input_schema().unwrap(), {
      "callId": "patch_1",
      "operation": { "type": "update_file", "path": "src/main.mbt" },
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(patch.output_schema().unwrap(), {
      "status": "completed",
      "output": "Done",
    }),
  )
  let computer = tools.computer()
  assert_true(
    @provider_utils.json_schema_matches(computer.input_schema().unwrap(), {
      "actions": [
        { "type": "click", "button": "left", "x": 10, "y": 20 },
        { "type": "keypress", "keys": ["CTRL", "L"] },
      ],
      "pendingSafetyChecks": [{ "id": "check_1" }],
      "status": "in_progress",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(computer.output_schema().unwrap(), {
      "output": {
        "type": "computer_screenshot",
        "imageUrl": "data:image/png;base64,AA==",
      },
    }),
  )
  let code = tools.code_interpreter()
  assert_true(
    @provider_utils.json_schema_matches(code.input_schema().unwrap(), {
      "code": null,
      "containerId": "ctr_1",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(code.output_schema().unwrap(), {
      "outputs": [
        { "type": "logs", "logs": "ok" },
        { "type": "image", "url": "https://example.com/plot.png" },
      ],
    }),
  )
  let programmatic = tools.programmatic_tool_calling()
  assert_true(
    @provider_utils.json_schema_matches(programmatic.input_schema().unwrap(), {
      "code": "return 1",
      "fingerprint": "fp_1",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(programmatic.output_schema().unwrap(), {
      "result": "1",
      "status": "completed",
    }),
  )
}

///|
async test "OpenAI application tools preserve execution and approval callbacks" {
  let events : Array[String] = []
  let tool = createOpenAI(api_key="test-key")
    .tools()
    .applyPatch(
      execute=(input, options) => {
        assert_eq(options.tool_call_id, "patch_1")
        let path = match input {
          { "operation": { "path": String(value), .. }, .. } => value
          _ => ""
        }
        events.push("execute:" + path)
        { "status": "completed", "output": "applied" }
      },
      needs_approval=@provider_utils.ToolNeedsApproval::when((input, options) => {
        assert_eq(options.tool_call_id, "patch_1")
        input is { "operation": { "type": "delete_file", .. }, .. }
      }),
      to_model_output=options => {
        events.push("output:" + options.tool_call_id)
        @provider_utils.ModelToolResultOutput::json(options.output)
      },
      on_input_start=options => events.push("start:" + options.tool_call_id),
      on_input_delta=options => events.push("delta:" + options.input_text_delta),
      on_input_available=options => {
        events.push("available:" + options.tool_call_id)
      },
    )
  let input : Json = {
    "callId": "patch_1",
    "operation": { "type": "delete_file", "path": "old.mbt" },
  }
  let execution_options = @provider_utils.ToolExecutionOptions::new(
    tool_call_id="patch_1",
  )
  tool.invoke_input_start(execution_options)
  tool.invoke_input_delta(
    @provider_utils.ToolInputDeltaOptions::new(
      input_text_delta="{",
      tool_call_id="patch_1",
    ),
  )
  tool.invoke_input_available(
    @provider_utils.ToolInputAvailableOptions::new(
      input~,
      tool_call_id="patch_1",
    ),
  )
  assert_eq(
    tool.resolve_needs_approval(
      input,
      @provider_utils.ToolNeedsApprovalOptions::new(tool_call_id="patch_1"),
    ),
    Some(true),
  )
  let output = tool.execute(input, execution_options).unwrap()
  assert_eq(output, { "status": "completed", "output": "applied" })
  assert_eq(
    tool.to_model_output(
      @provider_utils.ToolModelOutputOptions::new(
        tool_call_id="patch_1",
        input~,
        output~,
      ),
    ),
    @provider_utils.ModelToolResultOutput::json(output),
  )
  assert_eq(events, [
    "start:patch_1", "delta:{", "available:patch_1", "execute:old.mbt", "output:patch_1",
  ])
}

///|
async test "OpenAI provider-executed tools preserve streaming callbacks" {
  let events : Array[String] = []
  let tool = createOpenAI(api_key="test-key")
    .tools()
    .webSearch(
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
      input_text_delta="{}",
      tool_call_id="search_1",
    ),
  )
  tool.invoke_input_available(
    @provider_utils.ToolInputAvailableOptions::new(
      input=Json::empty_object(),
      tool_call_id="search_1",
    ),
  )
  assert_eq(events, ["start:search_1", "delta:{}", "available:{}"])
}

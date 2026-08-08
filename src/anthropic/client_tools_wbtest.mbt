///|
test "Anthropic bash tools expose application-executed factory semantics" {
  let tool = bash_20241022()
  assert_true(!tool.is_provider_executed())
  assert_true(tool.is_executable())
  assert_true(
    @provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
      "command": "pwd",
      "restart": false,
    }),
  )
  assert_true(
    !@provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
      "restart": true,
    }),
  )
  match tool.to_tool_definition("shell") {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "anthropic.bash_20241022")
      assert_eq(name, "shell")
      assert_eq(args, Json::empty_object())
    }
    _ => fail("expected Anthropic provider-defined bash tool")
  }
}

///|
async test "Anthropic bash tools use the execution sandbox by default" {
  let commands : Array[@provider_utils.SandboxProcessOptions] = []
  let sandbox = @provider_utils.SandboxSession::new(
    description="Anthropic test sandbox",
    run=options => {
      commands.push(options)
      @provider_utils.SandboxProcessResult::new(
        exit_code=0,
        stdout="/workspace\n",
      )
    },
  )
  let execution_options = @provider_utils.ToolExecutionOptions::new(
    tool_call_id="bash-1",
    experimental_sandbox=sandbox,
  )
  for tool in [bash_20241022(), bash_20250124()] {
    assert_eq(
      tool.execute({ "command": "pwd" }, execution_options),
      Some({ "exitCode": 0, "stdout": "/workspace\n", "stderr": "" }),
    )
  }
  assert_eq(commands.length(), 2)
  assert_eq(commands[0].command, "pwd")
  assert_eq(commands[1].command, "pwd")
}

///|
async test "Anthropic bash custom execution overrides the sandbox default" {
  let custom_calls = Ref(0)
  let tool = bash_20241022(execute=(_input, _options) => {
    custom_calls.val = custom_calls.val + 1
    { "custom": true }
  })
  assert_eq(
    tool.execute(
      { "command": "pwd" },
      @provider_utils.ToolExecutionOptions::new(tool_call_id="bash-2"),
    ),
    Some({ "custom": true }),
  )
  assert_eq(custom_calls.val, 1)
  assert_true(!bash_20241022(disable_default_execute=true).is_executable())
}

///|
test "Anthropic computer tool keeps SDK args and prepares wire fields" {
  let tool = computer_20251124(
    display_width_px=1920,
    display_height_px=1080,
    display_number=2,
    enable_zoom=true,
  )
  assert_true(!tool.is_provider_executed())
  assert_true(
    @provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
      "action": "zoom",
      "region": [10, 20, 300, 400],
    }),
  )
  assert_true(
    !@provider_utils.json_schema_matches(tool.input_schema().unwrap(), {
      "action": "zoom",
      "region": [10, 20, 300],
    }),
  )
  match tool.to_tool_definition("desktop") {
    @provider.ProviderTool(id~, name~, args~) => {
      assert_eq(id, "anthropic.computer_20251124")
      assert_eq(name, "desktop")
      assert_eq(args, {
        "displayWidthPx": 1920,
        "displayHeightPx": 1080,
        "displayNumber": 2,
        "enableZoom": true,
      })
    }
    _ => fail("expected Anthropic provider-defined computer tool")
  }
  let prepared = prepare_anthropic_v4_request(
    "claude-sonnet-4-6",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[
            @provider.V4PromptText(
              text="Use the desktop.",
              provider_options=Map([]),
            ),
          ],
          provider_options=Map([]),
        ),
      ]),
      tools=[
        @provider.LanguageModelV4Tool::from_tool_definition(
          tool.to_tool_definition("desktop"),
        ),
      ],
    ),
    "anthropic.messages",
    false,
  )
  assert_true(
    prepared.body
    is {
      "tools": [
        {
          "type": "computer_20251124",
          "name": "computer",
          "display_width_px": 1920,
          "display_height_px": 1080,
          "display_number": 2,
          "enable_zoom": true,
          ..
        },
      ],
      ..
    },
  )
}

///|
test "Anthropic text editor schemas preserve versioned undo support" {
  let undo : Json = { "command": "undo_edit", "path": "/workspace/main.mbt" }
  assert_true(
    @provider_utils.json_schema_matches(
      text_editor_20241022().input_schema().unwrap(),
      undo,
    ),
  )
  assert_true(
    @provider_utils.json_schema_matches(
      text_editor_20250124().input_schema().unwrap(),
      undo,
    ),
  )
  assert_true(
    !@provider_utils.json_schema_matches(
      text_editor_20250429().input_schema().unwrap(),
      undo,
    ),
  )
  assert_true(
    !@provider_utils.json_schema_matches(
      textEditor_20250728().input_schema().unwrap(),
      undo,
    ),
  )
  match textEditor_20250728(max_characters=12000).to_tool_definition("editor") {
    @provider.ProviderTool(id~, args~, ..) => {
      assert_eq(id, "anthropic.text_editor_20250728")
      assert_eq(args, { "maxCharacters": 12000 })
    }
    _ => fail("expected Anthropic provider-defined text editor")
  }
}

///|
test "Anthropic memory schema validates its discriminated commands" {
  let schema = memory_20250818().input_schema().unwrap()
  assert_true(
    @provider_utils.json_schema_matches(schema, {
      "command": "view",
      "path": "/memories",
      "view_range": [1, 10],
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(schema, {
      "command": "create",
      "path": "/memories/project.md",
      "file_text": "MoonBit",
    }),
  )
  assert_true(
    @provider_utils.json_schema_matches(schema, {
      "command": "rename",
      "old_path": "/memories/old.md",
      "new_path": "/memories/new.md",
    }),
  )
  assert_true(
    !@provider_utils.json_schema_matches(schema, {
      "command": "create",
      "path": "/memories/project.md",
    }),
  )
  assert_true(
    !@provider_utils.json_schema_matches(schema, {
      "command": "unknown",
      "path": "/memories",
    }),
  )
}

///|
async test "Anthropic client tools forward execution and input callbacks" {
  let events : Array[String] = []
  let tool = memory_20250818(
    execute=(input, options) => {
      events.push("execute:" + options.tool_call_id)
      assert_eq(input, { "command": "delete", "path": "/memories/old.md" })
      { "deleted": true }
    },
    on_input_start=options => events.push("start:" + options.tool_call_id),
    on_input_delta=options => events.push("delta:" + options.input_text_delta),
    on_input_available=options => {
      events.push("available:" + options.input.stringify())
    },
  )
  let options = @provider_utils.ToolExecutionOptions::new(
    tool_call_id="memory-1",
  )
  tool.invoke_input_start(options)
  tool.invoke_input_delta(
    @provider_utils.ToolInputDeltaOptions::new(
      input_text_delta="{\"command\":\"delete\"}",
      tool_call_id="memory-1",
    ),
  )
  tool.invoke_input_available(
    @provider_utils.ToolInputAvailableOptions::new(
      input={ "command": "delete", "path": "/memories/old.md" },
      tool_call_id="memory-1",
    ),
  )
  assert_eq(
    tool.execute({ "command": "delete", "path": "/memories/old.md" }, options),
    Some({ "deleted": true }),
  )
  assert_eq(events, [
    "start:memory-1", "delta:{\"command\":\"delete\"}", "available:{\"command\":\"delete\",\"path\":\"/memories/old.md\"}",
    "execute:memory-1",
  ])
}

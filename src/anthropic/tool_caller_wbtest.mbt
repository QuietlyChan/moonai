///|
test "code execution tools register versioned provider caller options" {
  for
    entry in [
      (code_execution_20250825(), "code_execution_20250825"),
      (code_execution_20260120(), "code_execution_20260120"),
    ] {
    let (tool, caller_name) = entry
    assert_true(tool.is_provider_executed())
    assert_true(tool.supports_deferred_results())
    let caller = @provider_utils.experimental_get_tool_caller(tool).unwrap()
    assert_true(caller.is_provider())
    let prepared = caller.prepare_provider_options(
      Map([
        ("anthropic", { "allowedCallers": ["direct"], "sendReasoning": true }),
      ]),
    )
    assert_eq(
      prepared.get("anthropic"),
      Some({ "allowedCallers": ["direct", caller_name], "sendReasoning": true }),
    )
  }
}

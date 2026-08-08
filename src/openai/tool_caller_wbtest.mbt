///|
test "programmatic tool calling registers provider caller options" {
  let tool = programmatic_tool_calling()
  assert_true(tool.is_provider_executed())
  assert_true(tool.supports_deferred_results())
  let caller = @provider_utils.experimental_get_tool_caller(tool).unwrap()
  assert_true(caller.is_provider())
  let prepared = caller.prepare_provider_options(
    Map([("openai", { "allowedCallers": ["direct"], "strictJsonSchema": true })]),
  )
  assert_eq(
    prepared.get("openai"),
    Some({
      "allowedCallers": ["direct", "programmatic"],
      "strictJsonSchema": true,
    }),
  )
  let prepared_twice = caller.prepare_provider_options(prepared)
  assert_eq(prepared_twice.get("openai"), prepared.get("openai"))
}

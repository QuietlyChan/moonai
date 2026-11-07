///|
test "function tools preserve optional description and strict settings" {
  let omitted = @provider.ToolDefinition::new("lookup", { "type": "object" })
  assert_eq(omitted.description(), None)
  assert_eq(omitted.strict_setting(), None)
  assert_eq(omitted.strict(), false)

  let explicit_false = @provider.ToolDefinition::new(
    "lookup",
    { "type": "object" },
    strict=false,
  )
  assert_eq(explicit_false.strict_setting(), Some(false))
  assert_eq(explicit_false.strict(), false)
}

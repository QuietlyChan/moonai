///|
test "DeepAgents gateway auth configures the Anthropic-compatible endpoint" {
  let env = resolveDeepAgentsEnv(
    auth=DeepAgentsGatewayAuth(
      api_key=Some("gateway-key"),
      base_url=Some("https://gateway.example/"),
    ),
    environment=Map([]),
  )
  assert_eq(env["AI_GATEWAY_API_KEY"], "gateway-key")
  assert_eq(env["ANTHROPIC_API_KEY"], "gateway-key")
  assert_eq(env["ANTHROPIC_BASE_URL"], "https://gateway.example")
}

///|
test "DeepAgents exposes Harness V1 tools and approval support" {
  let adapter = deepAgents as &@harness.HarnessV1
  assert_eq(adapter.harness_id(), "deepagents")
  assert_true(adapter.supports_builtin_tool_approvals())
  assert_true(adapter.supports_builtin_tool_filtering())
  let names : Array[String] = []
  for tool in adapter.builtin_tools() {
    match tool.wire_name() {
      Some(value) => names.push(value)
      None => ()
    }
  }
  assert_true(names.contains("read"))
  assert_true(names.contains("bash"))
  assert_true(names.contains("grep"))
}

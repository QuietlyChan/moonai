///|
test "Pi auth preserves custom provider environment" {
  let env = resolvePiEnv(
    options=PiCustomEnv({
      "OPENAI_API_KEY": "openai-key",
      "OPENAI_BASE_URL": "https://openai.example/v1",
      "EMPTY": "",
    }),
    environment=Map([]),
  )
  assert_eq(env["OPENAI_API_KEY"], "openai-key")
  assert_eq(env.get("EMPTY"), None)
}

///|
test "Pi resolves the gateway default model only with credentials" {
  assert_eq(
    resolve_pi_model(None, environment={ "AI_GATEWAY_API_KEY": "key" }),
    Some(DEFAULT_PI_GATEWAY_MODEL_ID),
  )
  assert_eq(resolve_pi_model(None, environment=Map([])), None)
  assert_eq(resolve_pi_model(Some("custom/model")), Some("custom/model"))
}

///|
test "Pi exposes filtering and familiar built-in tools" {
  let adapter = pi as &@harness.HarnessV1
  assert_eq(adapter.harness_id(), "pi")
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
  assert_true(names.contains("ls"))
}

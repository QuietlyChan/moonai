///|
test "OpenCode model coordinates match AI SDK behavior" {
  assert_eq(splitOpenCodeModel(Some("openai/gpt-5"), None), OpenCodeModelCoordinate::{
    provider_id: Some("openai"),
    model_id: Some("gpt-5"),
    model: Some("openai/gpt-5"),
  })
  assert_eq(splitOpenCodeModel(Some("gpt-5"), Some("openai")), OpenCodeModelCoordinate::{
    provider_id: Some("openai"),
    model_id: Some("gpt-5"),
    model: Some("openai/gpt-5"),
  })
  assert_eq(
    toOpenCodeGatewayBaseUrl("https://gateway.example/"),
    "https://gateway.example/v1",
  )
}

///|
test "OpenCode auth prefers explicit provider credentials" {
  let resolved = resolveOpenCodeEnv(
    auth=OpenCodeOpenAIAuth(
      api_key=Some("explicit"),
      base_url=Some("https://openai.example/v1"),
      organization=Some("org-1"),
      project=None,
    ),
    model="openai/gpt-5",
    environment={ "OPENAI_API_KEY": "ambient", "AI_GATEWAY_API_KEY": "gateway" },
  )
  assert_eq(resolved["OPENAI_API_KEY"], "explicit")
  assert_eq(resolved["OPENAI_ORGANIZATION"], "org-1")
  assert_eq(resolved.get("AI_GATEWAY_API_KEY"), None)
}

///|
test "OpenCode exposes stable Harness V1 metadata and tools" {
  let harness = createOpenCode()
  let adapter = harness as &@harness.HarnessV1
  assert_eq(adapter.specification_version(), "harness-v1")
  assert_eq(adapter.harness_id(), "opencode")
  assert_true(adapter.supports_builtin_tool_approvals())
  assert_true(adapter.builtin_tools().length() >= 6)
}

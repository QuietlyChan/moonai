///|
test "provider references resolve identifiers and retain typed failures" {
  let reference = ProviderReference::new(
    Map([("openai", "file-openai"), ("anthropic", "file-anthropic")]),
  )
  assert_eq(resolve_provider_reference(reference, "openai"), "file-openai")
  try resolve_provider_reference(reference, "missing") catch {
    NoSuchProviderReferenceError(provider~, available_providers~) => {
      assert_eq(provider, "missing")
      assert_eq(available_providers, ["openai", "anthropic"])
    }
  } noraise {
    _ => fail("expected a missing provider reference error")
  }
}

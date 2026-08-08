///|
test "custom provider prefers registered models and delegates fallback models" {
  let custom_model = @testing.MockChatModel::new(
    [],
    @provider.ChatResponse::empty(),
    provider_name="local",
    model_id="local-chat",
  )
  let custom_language_model = @model.as_language_model_v4(
    custom_model as &@provider.ChatModel,
  )
  let fallback = @openai.create_openai(api_key="test-key")
  let custom = custom_provider(
    language_models=Map([("local-chat", custom_language_model)]),
    fallback_provider=fallback,
  )
  let registry = ProviderRegistry::new().with_provider("composed", custom)
  assert_eq(custom.specification_version(), "v4")
  let local_model = registry.language_model("composed:local-chat")
  assert_eq(local_model.model_id(), "local-chat")
  assert_eq(local_model.provider(), "local")

  let fallback_model = registry.language_model("composed:gpt-4.1")
  assert_eq(fallback_model.model_id(), "gpt-4.1")
  assert_eq(fallback_model.provider(), "openai.responses")
  assert_eq(registry.files("composed").provider(), "openai.files")
  assert_eq(registry.skills("composed").provider(), "openai.skills")
}

///|
test "custom provider exposes typed missing-model failures" {
  let custom = custom_provider()
  try custom.language_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.LanguageModel)
    }
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected missing model")
  }
}

///|
test "custom provider omits an unconfigured files capability" {
  let custom = custom_provider()
  let provider = custom as &@provider.ProviderV4
  match provider.files() {
    Some(_) => fail("files should be absent")
    None => ()
  }
}

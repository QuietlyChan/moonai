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
    provider_name="composed",
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
  let custom = custom_provider(provider_name="composed")
  try custom.require_language_model("missing") catch {
    @model.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id.key(), "composed:missing")
      assert_eq(model_type, @model.Chat)
    }
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected missing model")
  }
}

///|
test "custom provider rejects an empty provider name" {
  let empty_name : String = ""
  try custom_provider(provider_name=empty_name) catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "provider_name")
      assert_true(message.contains("empty"))
    }
  } noraise {
    _ => fail("expected invalid provider name")
  }
}

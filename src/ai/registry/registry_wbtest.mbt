///|
test "provider registry raises typed resolution errors" {
  let responses = @open_responses.create_open_responses(
    provider_name="local-responses",
    url="https://example.com/v1/responses",
  )
  let registry = ProviderRegistry::new().with_provider("local", responses)
  try registry.language_model("unqualified-model") catch {
    InvalidRegistryModelIdError(value~, separator~, model_type~) => {
      assert_eq(value, "unqualified-model")
      assert_eq(separator, ":")
      assert_eq(model_type, @model.Chat)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected invalid registry id")
  }
  try registry.language_model("missing:model") catch {
    NoSuchProviderError(provider_id~, available_provider_ids~) => {
      assert_eq(provider_id, "missing")
      assert_eq(available_provider_ids, ["local"])
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing provider")
  }
  try registry.image_model("local:image-model") catch {
    @model.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id.key(), "local:image-model")
      assert_eq(model_type, @model.Image)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected unsupported image model")
  }
  try registry.files("local") catch {
    NoSuchProviderCapabilityError(provider_id~, capability~) => {
      assert_eq(provider_id, "local")
      assert_eq(capability, "files")
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected unsupported files capability")
  }
}

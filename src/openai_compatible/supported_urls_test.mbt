///|
test "OpenAI-compatible URL capabilities default empty and can be injected" {
  let default_model = openai_compatible(
    provider_name="custom",
    base_url="https://example.com/v1",
    model_id="model",
  )
  assert_eq(default_model.supported_urls().length(), 0)
  let configured_model = openai_compatible(
    provider_name="custom",
    base_url="https://example.com/v1",
    model_id="model",
    supported_urls=[
      @provider.SupportedUrlRule::new("application/pdf", [
        "^https://cdn\\.example\\.com/.*$",
      ]),
    ],
  )
  assert_true(
    @provider_utils.is_url_supported(
      media_type="application/pdf",
      url="https://cdn.example.com/document.pdf",
      supported_urls=configured_model.supported_urls(),
    ),
  )
  assert_eq(
    @provider_utils.is_url_supported(
      media_type="application/pdf",
      url="https://example.com/document.pdf",
      supported_urls=configured_model.supported_urls(),
    ),
    false,
  )
}

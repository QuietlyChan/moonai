///|
test "Anthropic supports native HTTP image and PDF URLs" {
  let model = anthropic("claude-test", api_key="test-key")
  let rules = model.supported_urls()
  assert_true(
    @provider_utils.is_url_supported(
      media_type="image/png",
      url="https://example.com/image.png",
      supported_urls=rules,
    ),
  )
  assert_true(
    @provider_utils.is_url_supported(
      media_type="application/pdf",
      url="https://example.com/document.pdf",
      supported_urls=rules,
    ),
  )
}

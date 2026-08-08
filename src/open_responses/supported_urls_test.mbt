///|
test "Open Responses supports native HTTP image URLs" {
  let model = create_open_responses(
    provider_name="test",
    url="https://example.com/v1/responses",
  ).language_model("test-model")
  assert_true(
    @provider_utils.is_url_supported(
      media_type="image/png",
      url="https://example.com/image.png",
      supported_urls=model.supported_urls(),
    ),
  )
  assert_eq(
    @provider_utils.is_url_supported(
      media_type="application/pdf",
      url="https://example.com/document.pdf",
      supported_urls=model.supported_urls(),
    ),
    false,
  )
}

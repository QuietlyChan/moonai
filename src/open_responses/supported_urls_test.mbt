///|
test "Open Responses supports native HTTP image URLs" {
  let model = open_responses(
    model_id="test-model",
    provider_name="test",
    url="https://example.com/v1/responses",
  )
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

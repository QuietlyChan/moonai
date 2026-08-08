///|
test "Alibaba chat supports native HTTP image URLs" {
  let model = create_alibaba(api_key="test-key").chat("qwen-test")
  assert_true(
    @provider_utils.is_url_supported(
      media_type="image/webp",
      url="https://example.com/image.webp",
      supported_urls=model.supported_urls(),
    ),
  )
}

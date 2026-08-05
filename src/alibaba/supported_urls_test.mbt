///|
test "Alibaba chat supports native HTTP image URLs" {
  let model = alibaba_chat("qwen-test")
  assert_true(
    @provider_utils.is_url_supported(
      media_type="image/webp",
      url="https://example.com/image.webp",
      supported_urls=model.supported_urls(),
    ),
  )
}

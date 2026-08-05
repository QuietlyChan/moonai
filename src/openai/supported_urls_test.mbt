///|
test "OpenAI Chat and Responses expose distinct native URL capabilities" {
  let provider = create_openai(api_key="test-key")
  let chat = provider.chat("gpt-4o")
  let responses = provider.responses("gpt-4o")
  assert_true(
    @provider_utils.is_url_supported(
      media_type="image/jpeg",
      url="https://example.com/image.jpg",
      supported_urls=chat.supported_urls(),
    ),
  )
  assert_eq(
    @provider_utils.is_url_supported(
      media_type="application/pdf",
      url="https://example.com/document.pdf",
      supported_urls=chat.supported_urls(),
    ),
    false,
  )
  assert_true(
    @provider_utils.is_url_supported(
      media_type="application/pdf",
      url="https://example.com/document.pdf",
      supported_urls=responses.supported_urls(),
    ),
  )
}

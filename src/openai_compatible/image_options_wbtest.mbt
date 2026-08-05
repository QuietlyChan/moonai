///|
async test "typed image size overrides the standard size in multipart edits" {
  let model = openai_compatible_image(
    provider_name="test-provider",
    base_url="https://example.test/v1",
    model_id="image-model",
  )
  let options = @provider.ImageCallOptions::new(
    "Edit the image",
    size="1024x1024",
    files=[
      @provider.ImageFile::bytes(
        data=b"IMAGE",
        media_type="image/png",
        filename="input.png",
      ),
    ],
    provider_options=OpenAICompatibleImageModelOptions::new(size="auto").to_provider_options(
      provider_name="testProvider",
    ),
  )
  let resolution = resolve_compatible_options(
    options.provider_options,
    model.provider_name,
    image_reserved_fields(),
  )
  let form_data = model.edit_form_data(options, resolution.values)
  assert_true(form_data.diagnostic_body.contains("name=\"size\"\r\n\r\nauto"))
  assert_false(form_data.diagnostic_body.contains("1024x1024"))
}

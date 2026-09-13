///|
fn vision_test_prompt(
  parts : Array[@provider.LanguageModelV4PromptPart],
) -> Json raise {
  let prepared = prepare_deepseek_v4_request(
    "deepseek-chat",
    @provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(content=parts, provider_options=Map([])),
      ]),
    ),
    "deepseek.chat",
    false,
    true,
    false,
    true,
  )
  match prepared.body {
    { "messages": Array(messages), .. } =>
      match messages[0] {
        { "content": content, .. } => content
        _ => fail("first DeepSeek message has no content field")
      }
    _ => fail("DeepSeek request body has no messages array")
  }
}

///|
test "DeepSeek vision sends inline image data as an image_url data URL" {
  let content = vision_test_prompt([
    @provider.V4PromptText(text="What is this?", provider_options=Map([])),
    @provider.V4PromptFile(
      data=@provider.V4FileData("aW1hZ2U"),
      media_type="image/png",
      filename=None,
      provider_options=Map([]),
    ),
  ])
  assert_eq(
    content.stringify(),
    "[{\"type\":\"text\",\"text\":\"What is this?\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,aW1hZ2U\"}}]",
  )
}

///|
test "DeepSeek vision normalizes image/jpg to image/jpeg in data URLs" {
  let content = vision_test_prompt([
    @provider.V4PromptFile(
      data=@provider.V4FileData("aW1hZ2U"),
      media_type="image/jpg",
      filename=None,
      provider_options=Map([]),
    ),
  ])
  assert_true(content.stringify().contains("data:image/jpeg;base64,aW1hZ2U"))
}

///|
test "DeepSeek vision forwards imageDetail as the URL detail field" {
  let content = vision_test_prompt([
    @provider.V4PromptFile(
      data=@provider.V4FileUrl("https://example.test/cat.png"),
      media_type="image/png",
      filename=None,
      provider_options={ "deepseek": { "imageDetail": "low" } },
    ),
  ])
  assert_eq(
    content.stringify(),
    "[{\"type\":\"image_url\",\"image_url\":{\"url\":\"https://example.test/cat.png\",\"detail\":\"low\"}}]",
  )
}

///|
test "DeepSeek vision sends file references as file_id parts" {
  let content = vision_test_prompt([
    @provider.V4PromptFile(
      data=@provider.V4FileReference(
        @provider.ProviderReference::single(provider="deepseek", id="file-1"),
      ),
      media_type="image/png",
      filename=None,
      provider_options=Map([]),
    ),
  ])
  assert_eq(content.stringify(), "[{\"type\":\"file\",\"file_id\":\"file-1\"}]")
}

///|
test "DeepSeek vision fileData sends inline data as a file part" {
  let content = vision_test_prompt([
    @provider.V4PromptFile(
      data=@provider.V4FileData("aW1hZ2U"),
      media_type="image/webp",
      filename=Some("photo.webp"),
      provider_options={ "deepseek": { "fileData": true } },
    ),
  ])
  assert_eq(
    content.stringify(),
    "[{\"type\":\"file\",\"file_data\":\"data:image/webp;base64,aW1hZ2U\",\"filename\":\"photo.webp\"}]",
  )
}

///|
test "DeepSeek vision rejects imageDetail combined with fileData" {
  let outcome = try {
    let _ = vision_test_prompt([
      @provider.V4PromptFile(
        data=@provider.V4FileData("aW1hZ2U"),
        media_type="image/png",
        filename=None,
        provider_options={
          "deepseek": { "fileData": true, "imageDetail": "high" },
        },
      ),
    ])
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.InvalidPromptError(_)))
}

///|
test "DeepSeek vision rejects fileData with URL parts" {
  let outcome = try {
    let _ = vision_test_prompt([
      @provider.V4PromptFile(
        data=@provider.V4FileUrl("https://example.test/cat.png"),
        media_type="image/png",
        filename=None,
        provider_options={ "deepseek": { "fileData": true } },
      ),
    ])
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.InvalidPromptError(_)))
}

///|
test "DeepSeek vision rejects over-long image URLs" {
  let long_path = "abcdefghij".repeat(900)
  let outcome = try {
    let _ = vision_test_prompt([
      @provider.V4PromptFile(
        data=@provider.V4FileUrl("https://example.test/\{long_path}"),
        media_type="image/png",
        filename=None,
        provider_options=Map([]),
      ),
    ])
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.InvalidPromptError(_)))
}

///|
test "DeepSeek vision rejects unsupported image media types" {
  let outcome = try {
    let _ = vision_test_prompt([
      @provider.V4PromptFile(
        data=@provider.V4FileData("ZGF0YQ"),
        media_type="image/heic",
        filename=None,
        provider_options=Map([]),
      ),
    ])
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.UnsupportedFunctionalityError(_)))
}

///|
test "DeepSeek keeps text-only user messages as string content" {
  let content = vision_test_prompt([
    @provider.V4PromptText(text="plain text", provider_options=Map([])),
  ])
  assert_eq(content, Json::string("plain text"))
}

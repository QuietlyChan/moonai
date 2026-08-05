///|
test "URL support returns false without rules" {
  assert_eq(
    is_url_supported(
      media_type="text/plain",
      url="https://example.com/file.txt",
      supported_urls=[],
    ),
    false,
  )
}

///|
test "URL support matches exact media types and lower-case URLs" {
  let rules = [
    @provider.SupportedUrlRule::new("TEXT/PLAIN", [
      "^https://example\\.com/path$",
    ]),
  ]
  assert_true(
    is_url_supported(
      media_type="text/plain",
      url="HTTPS://EXAMPLE.COM/PATH",
      supported_urls=rules,
    ),
  )
  assert_eq(
    is_url_supported(
      media_type="image/png",
      url="https://example.com/path",
      supported_urls=rules,
    ),
    false,
  )
}

///|
test "URL support handles subtype and global wildcards" {
  let image_rules = [@provider.SupportedUrlRule::http("image/*")]
  assert_true(
    is_url_supported(
      media_type="image/png",
      url="https://example.com/image.png",
      supported_urls=image_rules,
    ),
  )
  assert_true(
    is_url_supported(
      media_type="image",
      url="http://example.com/image.png",
      supported_urls=image_rules,
    ),
  )
  assert_eq(
    is_url_supported(
      media_type="audio/mpeg",
      url="https://example.com/audio.mp3",
      supported_urls=image_rules,
    ),
    false,
  )
  assert_true(
    is_url_supported(media_type="video/mp4", url="custom://asset/1", supported_urls=[
      @provider.SupportedUrlRule::all("*"),
    ]),
  )
}

///|
test "top-level media types do not match concrete subtype rules" {
  let rules = [@provider.SupportedUrlRule::http("image/png")]
  assert_eq(
    isUrlSupported(
      media_type="image",
      url="https://example.com/image.png",
      supported_urls=rules,
    ),
    false,
  )
  assert_true(
    is_url_supported(
      media_type="image/png",
      url="https://example.com/image.png",
      supported_urls=rules,
    ),
  )
}

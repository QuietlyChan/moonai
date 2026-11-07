///|
test "V4 middleware contracts belong to the provider package" {
  assert_eq(
    @provider.LanguageModelV4Middleware::new().specification_version(),
    "v4",
  )
  assert_eq(
    @provider.EmbeddingModelV4Middleware::new().specification_version(),
    "v4",
  )
  assert_eq(
    @provider.ImageModelV4Middleware::new().specification_version(),
    "v4",
  )
}

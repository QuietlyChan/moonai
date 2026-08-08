///|
test "V4 middleware contracts belong to the provider package" {
  assert_eq(LanguageModelV4Middleware::new().specification_version(), "v4")
  assert_eq(EmbeddingModelV4Middleware::new().specification_version(), "v4")
  assert_eq(ImageModelV4Middleware::new().specification_version(), "v4")
}

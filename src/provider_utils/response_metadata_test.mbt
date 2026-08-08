///|
test "language model response metadata normalizes common provider fields" {
  let metadata = create_language_model_response_metadata(
    id="response-1",
    model="model-1",
    created=1_700_000_000,
  )
  assert_eq(metadata.id, Some("response-1"))
  assert_eq(metadata.model_id, Some("model-1"))
  assert_eq(metadata.created_at, Some(1_700_000_000))
  assert_eq(metadata.status_code, None)
  assert_eq(metadata.headers.length(), 0)
  assert_eq(metadata.body, None)
}

///|
test "language model response metadata preserves missing fields" {
  let metadata = createLanguageModelResponseMetadata()
  assert_true(metadata.is_empty())
}

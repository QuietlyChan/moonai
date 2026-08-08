///|
/// Convert the response identity fields shared by language-model providers
/// into provider-neutral metadata.
///
/// Provider adapters remain responsible for reading their wire format and
/// passing the corresponding `id`, `model`, and Unix timestamp fields.
pub fn create_language_model_response_metadata(
  id? : String,
  model? : String,
  created? : Int,
) -> @provider.ResponseMetadata {
  @provider.ResponseMetadata::new(id?, model_id?=model, created_at?=created)
}

///|
/// AI SDK-style spelling of `create_language_model_response_metadata`.
pub fn createLanguageModelResponseMetadata(
  id? : String,
  model? : String,
  created? : Int,
) -> @provider.ResponseMetadata {
  create_language_model_response_metadata(id?, model?, created?)
}

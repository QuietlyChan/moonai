///|
/// Raised when a provider registry cannot find a registered provider id.
pub(all) suberror NoSuchProviderError {
  NoSuchProviderError(
    provider_id~ : String,
    available_provider_ids~ : Array[String]
  )
} derive(Debug, Eq)

///|
/// Return the missing provider id.
pub fn NoSuchProviderError::provider_id(self : NoSuchProviderError) -> String {
  match self {
    NoSuchProviderError(provider_id~, ..) => provider_id
  }
}

///|
/// Return a copy of the registered provider ids available at failure time.
pub fn NoSuchProviderError::available_provider_ids(
  self : NoSuchProviderError,
) -> Array[String] {
  match self {
    NoSuchProviderError(available_provider_ids~, ..) =>
      available_provider_ids.copy()
  }
}

///|
/// Raised when a registry model id does not contain a non-empty provider and
/// model component separated by the configured separator.
pub(all) suberror InvalidRegistryModelIdError {
  InvalidRegistryModelIdError(
    value~ : String,
    separator~ : String,
    model_type~ : @model.ModelType
  )
} derive(Debug, Eq)

///|
/// Raised when a provider exists but does not expose a provider-level service.
pub(all) suberror NoSuchProviderCapabilityError {
  NoSuchProviderCapabilityError(provider_id~ : String, capability~ : String)
} derive(Debug, Eq)

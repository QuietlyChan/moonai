///|
/// Resolve a provider-specific identifier from a shared file reference.
pub fn resolve_provider_reference(
  reference : @provider.ProviderReference,
  provider : String,
) -> String raise @provider.NoSuchProviderReferenceError {
  @provider.resolve_provider_reference(reference, provider)
}

///|
/// AI SDK-style spelling for `resolve_provider_reference`.
pub fn resolveProviderReference(
  reference : @provider.ProviderReference,
  provider : String,
) -> String raise @provider.NoSuchProviderReferenceError {
  resolve_provider_reference(reference, provider)
}

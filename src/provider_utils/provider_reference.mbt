///|
/// Resolve a provider-specific identifier from a shared file reference.
pub fn resolve_provider_reference(
  reference : @provider.ProviderReference,
  provider : String,
) -> String raise @provider.NoSuchProviderReferenceError {
  @provider.resolve_provider_reference(reference, provider)
}

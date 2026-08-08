///|
/// Validate an optional provider base URL before applying environment or
/// provider-specific normalization.
///
/// The original value is returned unchanged when it is non-empty. Keeping
/// whitespace around a non-empty URL is intentional; URL parsing belongs to
/// the transport layer, while this guard only rejects values that cannot be a
/// meaningful endpoint.
pub fn validate_base_url(
  base_url : String?,
) -> String? raise @provider.InvalidArgumentError {
  match base_url {
    Some(value) if value.trim() == "" =>
      raise @provider.InvalidArgumentError(
        argument="baseURL",
        message="baseURL must be a non-empty string.",
      )
    _ => base_url
  }
}

///|
/// AI SDK-style camel-case spelling.
pub fn validateBaseURL(
  base_url : String?,
) -> String? raise @provider.InvalidArgumentError {
  validate_base_url(base_url)
}

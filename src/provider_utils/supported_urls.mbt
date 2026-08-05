///|
/// Check whether a URL can be passed to a model without downloading it.
///
/// Media types and URLs are normalized to lower case. A rule may target an
/// exact media type, a subtype wildcard such as `image/*`, or the global `*`
/// and `*/*` wildcards. A top-level-only media type such as `image` matches
/// `image/*`, but deliberately does not match a concrete `image/png` rule.
pub fn is_url_supported(
  media_type~ : String,
  url~ : String,
  supported_urls~ : Array[@provider.SupportedUrlRule],
) -> Bool {
  let normalized_media_type = media_type.to_lower()
  let normalized_url = url.to_lower()
  let is_top_level_only = !normalized_media_type.contains("/")
  for rule in supported_urls {
    let rule_media_type = rule.media_type().to_lower()
    let media_type_prefix = match rule_media_type {
      "*" | "*/*" => ""
      value => value.replace(old="*", new="")
    }
    let media_type_matches = if media_type_prefix == "" {
      true
    } else if is_top_level_only {
      "\{normalized_media_type}/" == media_type_prefix
    } else {
      normalized_media_type.has_prefix(media_type_prefix)
    }
    if media_type_matches && rule.matches_url(normalized_url) {
      return true
    }
  }
  false
}

///|
/// AI SDK-style camel-case spelling for `is_url_supported`.
pub fn isUrlSupported(
  media_type~ : String,
  url~ : String,
  supported_urls~ : Array[@provider.SupportedUrlRule],
) -> Bool {
  is_url_supported(media_type~, url~, supported_urls~)
}

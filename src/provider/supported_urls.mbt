///|
/// One media-type entry in a language model's native URL capability map.
///
/// URL patterns are regular expressions and are evaluated against lower-case
/// URLs, matching the AI SDK `supportedUrls` contract.
pub struct SupportedUrlRule {
  priv media_type : String
  priv pattern_sources : Array[String]
  priv patterns : Array[Regex]
}

///|
/// Create a native URL rule from regular-expression source strings.
pub fn SupportedUrlRule::new(
  media_type : String,
  url_patterns : Array[String],
) -> SupportedUrlRule raise {
  let pattern_sources = url_patterns.copy()
  let patterns = [ for pattern in pattern_sources => Regex(pattern) ]
  { media_type, pattern_sources, patterns }
}

///|
/// Create the common rule for HTTP and HTTPS URLs of one media type.
pub fn SupportedUrlRule::http(media_type : String) -> SupportedUrlRule {
  {
    media_type,
    pattern_sources: ["^https?://.*$"],
    patterns: [re"^https?://.*$"],
  }
}

///|
/// Create a rule that accepts every URL for one media type.
pub fn SupportedUrlRule::all(media_type : String) -> SupportedUrlRule {
  { media_type, pattern_sources: [".*"], patterns: [re".*"] }
}

///|
/// Return the case-insensitive media-type selector for this rule.
pub fn SupportedUrlRule::media_type(self : SupportedUrlRule) -> String {
  self.media_type
}

///|
/// Return a defensive copy of the configured regular-expression sources.
pub fn SupportedUrlRule::url_patterns(self : SupportedUrlRule) -> Array[String] {
  self.pattern_sources.copy()
}

///|
/// Test a normalized lower-case URL against this rule's patterns.
pub fn SupportedUrlRule::matches_url(
  self : SupportedUrlRule,
  normalized_url : String,
) -> Bool {
  for pattern in self.patterns {
    if pattern.execute(normalized_url) is Some(_) {
      return true
    }
  }
  false
}

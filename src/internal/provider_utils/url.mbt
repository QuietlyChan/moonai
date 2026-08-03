///|
/// Remove one trailing slash from a provider endpoint.
pub fn without_trailing_slash(url : String) -> String {
  url.strip_suffix("/").unwrap_or(url).to_owned()
}

///|
/// Append a path unless the configured endpoint already ends with it.
pub fn append_path(url : String, path : String) -> String {
  let base = without_trailing_slash(url)
  let normalized_path = if path.has_prefix("/") { path } else { "/\{path}" }
  if base.has_suffix(normalized_path) {
    base
  } else {
    "\{base}\{normalized_path}"
  }
}

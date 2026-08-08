///|
/// Alibaba prompt-cache control attached to a message or content part.
///
/// Alibaba currently documents `ephemeral`, while the open string keeps the
/// type forward-compatible with provider additions, matching AI SDK.
pub(all) struct AlibabaCacheControl {
  cache_type : String
} derive(Debug, Eq)

///|
/// Construct a typed Alibaba cache-control marker.
pub fn AlibabaCacheControl::new(cache_type~ : String) -> AlibabaCacheControl {
  { cache_type, }
}

///|
/// Convert a cache-control marker into Alibaba's provider-options namespace.
pub fn AlibabaCacheControl::to_provider_options(
  self : AlibabaCacheControl,
) -> Map[String, Json] {
  { "alibaba": { "cacheControl": { "type": self.cache_type } } }
}

///|
fn alibaba_cache_control(options : Map[String, Json]) -> Json? {
  match options.get("alibaba") {
    Some(Object(values)) =>
      match values.get("cacheControl") {
        Some(Null) | None =>
          match values.get("cache_control") {
            Some(Null) | None => None
            Some(value) => Some(value)
          }
        Some(value) => Some(value)
      }
    _ => None
  }
}

///|
fn record_alibaba_cache_control(
  value : Json?,
  count : Ref[Int],
  warnings : Array[@provider.Warning],
) -> Json? {
  guard value is Some(cache_control) else { return None }
  count.val = count.val + 1
  if count.val > 4 {
    warnings.push(
      @provider.Warning::Other(
        message="Max breakpoint limit exceeded. Only the last 4 cache markers will take effect.",
      ),
    )
  }
  Some(cache_control)
}

///|
fn alibaba_text_block(text : String, cache_control : Json?) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("text")),
        ("text", Json::string(text)),
        ..if cache_control is Some(value) {
          [("cache_control", value)]
        },
      ],
    ),
  )
}

///|
/// Read a string field from a JSON object.
pub fn json_string_field(json : Json, field : String) -> String? {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
/// Read an integer-valued number field from a JSON object.
pub fn json_int_field_opt(json : Json, field : String) -> Int? {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(Number(value, ..)) => Some(value.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Read an integer-valued number field or return the supplied default.
pub fn json_int_field(json : Json, field : String, default? : Int = 0) -> Int {
  json_int_field_opt(json, field).unwrap_or(default)
}

///|
/// Extract provider-specific metadata using the naming conventions used by
/// current AI providers. The returned map is keyed by provider name, matching
/// the AI SDK provider-metadata contract.
pub fn provider_metadata_from_json(
  json : Json,
  provider_name : String,
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  let metadata = match json {
    Object(object) =>
      match object.get("provider_metadata") {
        Some(value) => Some(value)
        None => object.get("providerMetadata")
      }
    _ => None
  }
  match metadata {
    Some(metadata_value) =>
      match metadata_value {
        Object(value) =>
          // Some gateways already return an outer provider-keyed object.
          if value.get(provider_name) is Some(_) || all_object_values(value) {
            for entry in value.iter2() {
              let (key, item) = entry
              result[key] = item
            }
          } else {
            result[provider_name] = metadata_value
          }
        _ => result[provider_name] = metadata_value
      }
    None => ()
  }
  result
}

///|
/// Provider metadata is conventionally an object whose values are provider
/// objects. This lets gateways use a provider key that differs from the
/// model's endpoint suffix (for example `openai` vs `openai.chat`).
fn all_object_values(value : Map[String, Json]) -> Bool {
  guard value.length() > 0 else { return false }
  for entry in value.iter2() {
    let (_, item) = entry
    match item {
      Object(_) => ()
      _ => return false
    }
  }
  true
}

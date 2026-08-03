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

///|
fn anthropic_supported_string_format(value : String) -> Bool {
  value == "date-time" ||
  value == "time" ||
  value == "date" ||
  value == "duration" ||
  value == "email" ||
  value == "hostname" ||
  value == "uri" ||
  value == "ipv4" ||
  value == "ipv6" ||
  value == "uuid"
}

///|
fn anthropic_constraint_keys() -> Array[String] {
  [
    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength",
    "maxLength", "pattern", "minItems", "maxItems", "uniqueItems", "minProperties",
    "maxProperties", "not",
  ]
}

///|
fn anthropic_constraint_name(value : String) -> String {
  let output = StringBuilder::new(size_hint=value.length() + 4)
  for character in value {
    if character.is_ascii_uppercase() {
      output.write_char(' ')
      output.write_char(character.to_ascii_lowercase())
    } else {
      output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn anthropic_constraint_value(value : Json) -> String {
  match value {
    String(text) => text
    _ => value.stringify()
  }
}

///|
fn anthropic_constraint_description(schema : Map[String, Json]) -> String? {
  let descriptions : Array[String] = []
  for key in anthropic_constraint_keys() {
    match schema.get(key) {
      Some(Null) | Some(False) | None => ()
      Some(value) =>
        descriptions.push(
          "\{anthropic_constraint_name(key)}: \{anthropic_constraint_value(value)}",
        )
    }
  }
  match schema.get("format") {
    Some(String(value)) if !anthropic_supported_string_format(value) =>
      descriptions.push("format: \{value}")
    _ => ()
  }
  if descriptions.length() == 0 {
    None
  } else {
    Some(descriptions.join("; ") + ".")
  }
}

///|
fn sanitize_anthropic_definition(value : Json) -> Json {
  match value {
    True | False => value
    Object(_) => sanitize_anthropic_schema(value)
    _ => value
  }
}

///|
fn sanitize_anthropic_definition_array(value : Json) -> Json? {
  match value {
    Array(values) =>
      Some(
        Json::array(
          [
            for definition in values => {
              sanitize_anthropic_definition(definition)
            }
          ],
        ),
      )
    _ => None
  }
}

///|
fn sanitize_anthropic_definition_map(value : Json) -> Json? {
  match value {
    Object(values) => {
      let sanitized : Map[String, Json] = Map([])
      for entry in values.iter2() {
        sanitized[entry.0] = sanitize_anthropic_definition(entry.1)
      }
      Some(Json::object(sanitized))
    }
    _ => None
  }
}

///|
fn copy_anthropic_schema_field(
  source : Map[String, Json],
  target : Map[String, Json],
  name : String,
) -> Unit {
  if source.get(name) is Some(value) {
    target[name] = value
  }
}

///|
fn sanitize_anthropic_schema(value : Json) -> Json {
  guard value is Object(schema) else { return value }
  if schema.get("$ref") is Some(reference) {
    return Json::object(Map([("$ref", reference)]))
  }
  let result : Map[String, Json] = Map([])
  for
    field in [
      "$schema", "$id", "title", "description", "default", "const", "enum", "type",
    ] {
    copy_anthropic_schema_field(schema, result, field)
  }
  match schema.get("anyOf") {
    Some(any_of) =>
      if sanitize_anthropic_definition_array(any_of) is Some(sanitized) {
        result["anyOf"] = sanitized
      }
    None =>
      if schema.get("oneOf") is Some(one_of) &&
        sanitize_anthropic_definition_array(one_of) is Some(sanitized) {
        result["anyOf"] = sanitized
      }
  }
  if schema.get("allOf") is Some(all_of) &&
    sanitize_anthropic_definition_array(all_of) is Some(sanitized) {
    result["allOf"] = sanitized
  }
  if schema.get("definitions") is Some(definitions) &&
    sanitize_anthropic_definition_map(definitions) is Some(sanitized) {
    result["definitions"] = sanitized
  }
  if schema.get("$defs") is Some(definitions) &&
    sanitize_anthropic_definition_map(definitions) is Some(sanitized) {
    result["$defs"] = sanitized
  }
  let object_schema = schema.get("type") == Some(Json::string("object")) ||
    schema.get("properties") is Some(_)
  if object_schema {
    match schema.get("properties") {
      Some(Object(properties)) => {
        let sanitized : Map[String, Json] = Map([])
        for entry in properties.iter2() {
          sanitized[entry.0] = sanitize_anthropic_definition(entry.1)
        }
        result["properties"] = Json::object(sanitized)
      }
      _ => ()
    }
    result["additionalProperties"] = Json::boolean(false)
    copy_anthropic_schema_field(schema, result, "required")
  }
  match schema.get("items") {
    Some(Array(items)) =>
      result["items"] = Json::array(
        [
          for item in items => sanitize_anthropic_definition(item)
        ],
      )
    Some(item) => result["items"] = sanitize_anthropic_definition(item)
    None => ()
  }
  match schema.get("format") {
    Some(String(format)) if anthropic_supported_string_format(format) =>
      result["format"] = Json::string(format)
    _ => ()
  }
  if anthropic_constraint_description(schema) is Some(description) {
    result["description"] = Json::string(
      match result.get("description") {
        Some(String(existing)) => existing + "\n" + description
        _ => description
      },
    )
  }
  Json::object(result)
}

///|
/// Remove JSON Schema keywords rejected by Anthropic's constrained decoder.
/// Unsupported constraints are retained as readable descriptions so the model
/// still receives their intent.
pub fn sanitize_json_schema(schema : Json) -> Json {
  sanitize_anthropic_schema(schema)
}

///|
/// Camel-case alias matching AI SDK's internal utility name.
pub fn sanitizeJsonSchema(schema : Json) -> Json {
  sanitize_json_schema(schema)
}

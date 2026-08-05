///|
/// A JSON Schema validation failure with a JSONPath-like location.
pub suberror JsonSchemaValidationError {
  JsonSchemaValidationError(path~ : String, message~ : String)
} derive(Debug)

///|
fn schema_error(
  path : String,
  message : String,
) -> Unit raise JsonSchemaValidationError {
  raise JsonSchemaValidationError(path~, message~)
}

///|
fn schema_path_property(path : String, name : String) -> String {
  if name == "" {
    path + "[\"\"]"
  } else {
    path + "." + name
  }
}

///|
fn schema_path_index(path : String, index : Int) -> String {
  path + "[" + index.to_string() + "]"
}

///|
fn schema_int_field(schema : Map[String, Json], name : String) -> Int? {
  match schema.get(name) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn schema_double_field(schema : Map[String, Json], name : String) -> Double? {
  match schema.get(name) {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn json_is_integer(value : Json) -> Bool {
  match value {
    Number(number, ..) => number.to_int().to_double() == number
    _ => false
  }
}

///|
fn json_type_matches(expected : String, value : Json) -> Bool {
  match expected {
    "object" => value is Object(_)
    "array" => value is Array(_)
    "string" => value is String(_)
    "number" => value is Number(_, ..)
    "integer" => json_is_integer(value)
    "boolean" => value is True || value is False
    "null" => value is Null
    _ => true
  }
}

///|
fn schema_type_matches(schema : Map[String, Json], value : Json) -> Bool {
  match schema.get("type") {
    Some(String(expected)) => json_type_matches(expected, value)
    Some(Array(types)) => {
      for item in types {
        match item {
          String(expected) if json_type_matches(expected, value) => return true
          _ => ()
        }
      }
      false
    }
    _ => true
  }
}

///|
fn schema_matches(schema : Json, value : Json) -> Bool {
  try validate_json_schema_at(schema, value, "$") catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn validate_required(
  schema : Map[String, Json],
  value : Map[String, Json],
  path : String,
) -> Unit raise JsonSchemaValidationError {
  match schema.get("required") {
    Some(Array(required)) =>
      for name in required {
        match name {
          String(field) =>
            if value.get(field) is None {
              schema_error(
                schema_path_property(path, field),
                "required property is missing",
              )
            }
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn validate_object(
  schema : Map[String, Json],
  value : Map[String, Json],
  path : String,
) -> Unit raise JsonSchemaValidationError {
  match schema_int_field(schema, "minProperties") {
    Some(minimum) if value.length() < minimum =>
      schema_error(path, "object has fewer than minProperties")
    _ => ()
  }
  match schema_int_field(schema, "maxProperties") {
    Some(maximum) if value.length() > maximum =>
      schema_error(path, "object has more than maxProperties")
    _ => ()
  }
  validate_required(schema, value, path)
  let properties = match schema.get("properties") {
    Some(Object(properties)) => Some(properties)
    _ => None
  }
  for entry in value.iter2() {
    let (name, item) = entry
    let item_path = schema_path_property(path, name)
    match properties {
      Some(fields) =>
        match fields.get(name) {
          Some(item_schema) =>
            validate_json_schema_at(item_schema, item, item_path)
          None =>
            match schema.get("additionalProperties") {
              Some(False) =>
                schema_error(item_path, "additional property is not allowed")
              Some(additional_schema) if additional_schema is Object(_) ||
                additional_schema is True =>
                if additional_schema is Object(_) {
                  validate_json_schema_at(additional_schema, item, item_path)
                }
              _ => ()
            }
        }
      None =>
        match schema.get("additionalProperties") {
          Some(False) =>
            schema_error(item_path, "additional property is not allowed")
          Some(additional_schema) if additional_schema is Object(_) =>
            validate_json_schema_at(additional_schema, item, item_path)
          _ => ()
        }
    }
  }
}

///|
fn validate_array(
  schema : Map[String, Json],
  values : Array[Json],
  path : String,
) -> Unit raise JsonSchemaValidationError {
  match schema_int_field(schema, "minItems") {
    Some(minimum) if values.length() < minimum =>
      schema_error(path, "array has fewer than minItems")
    _ => ()
  }
  match schema_int_field(schema, "maxItems") {
    Some(maximum) if values.length() > maximum =>
      schema_error(path, "array has more than maxItems")
    _ => ()
  }
  match schema.get("uniqueItems") {
    Some(True) =>
      for index, value in values {
        for previous in 0..<index {
          if values[previous] == value {
            schema_error(
              schema_path_index(path, index),
              "array items must be unique",
            )
          }
        }
      }
    _ => ()
  }
  match schema.get("items") {
    Some(item_schema) if item_schema is Object(_) ||
      item_schema is True ||
      item_schema is False =>
      for index, value in values {
        validate_json_schema_at(
          item_schema,
          value,
          schema_path_index(path, index),
        )
      }
    _ => ()
  }
}

///|
fn validate_string(
  schema : Map[String, Json],
  value : String,
  path : String,
) -> Unit raise JsonSchemaValidationError {
  match schema_int_field(schema, "minLength") {
    Some(minimum) if value.length() < minimum =>
      schema_error(path, "string is shorter than minLength")
    _ => ()
  }
  match schema_int_field(schema, "maxLength") {
    Some(maximum) if value.length() > maximum =>
      schema_error(path, "string is longer than maxLength")
    _ => ()
  }
}

///|
fn validate_number(
  schema : Map[String, Json],
  value : Double,
  path : String,
) -> Unit raise JsonSchemaValidationError {
  match schema_double_field(schema, "minimum") {
    Some(minimum) if value < minimum =>
      schema_error(path, "number is below minimum")
    _ => ()
  }
  match schema_double_field(schema, "maximum") {
    Some(maximum) if value > maximum =>
      schema_error(path, "number is above maximum")
    _ => ()
  }
  match schema_double_field(schema, "exclusiveMinimum") {
    Some(minimum) if value <= minimum =>
      schema_error(path, "number is not above exclusiveMinimum")
    _ => ()
  }
  match schema_double_field(schema, "exclusiveMaximum") {
    Some(maximum) if value >= maximum =>
      schema_error(path, "number is not below exclusiveMaximum")
    _ => ()
  }
}

///|
fn validate_json_schema_at(
  schema : Json,
  value : Json,
  path : String,
) -> Unit raise JsonSchemaValidationError {
  match schema {
    True => return
    False => schema_error(path, "schema rejects this value")
    Object(fields) => {
      match fields.get("const") {
        Some(expected) if expected != value =>
          schema_error(path, "value does not match const")
        _ => ()
      }
      match fields.get("enum") {
        Some(Array(values)) => {
          let mut found = false
          for expected in values {
            if expected == value {
              found = true
              break
            }
          }
          if !found {
            schema_error(path, "value is not in enum")
          }
        }
        _ => ()
      }
      match fields.get("allOf") {
        Some(Array(schemas)) =>
          for nested in schemas {
            validate_json_schema_at(nested, value, path)
          }
        _ => ()
      }
      match fields.get("anyOf") {
        Some(Array(schemas)) => {
          let mut matched = false
          for nested in schemas {
            if schema_matches(nested, value) {
              matched = true
              break
            }
          }
          if !matched {
            schema_error(path, "value does not match anyOf")
          }
        }
        _ => ()
      }
      match fields.get("oneOf") {
        Some(Array(schemas)) => {
          let mut matches = 0
          for nested in schemas {
            if schema_matches(nested, value) {
              matches = matches + 1
            }
          }
          if matches != 1 {
            schema_error(path, "value does not match exactly one oneOf schema")
          }
        }
        _ => ()
      }
      match fields.get("not") {
        Some(nested) if schema_matches(nested, value) =>
          schema_error(path, "value matches forbidden not schema")
        _ => ()
      }
      if !schema_type_matches(fields, value) {
        schema_error(path, "value has the wrong JSON type")
      }
      match value {
        Object(object) => validate_object(fields, object, path)
        Array(values) => validate_array(fields, values, path)
        String(text) => validate_string(fields, text, path)
        Number(number, ..) => validate_number(fields, number, path)
        _ => ()
      }
    }
    _ => ()
  }
}

///|
/// Validate a JSON value against the supported JSON Schema vocabulary.
///
/// Unknown schema keywords are intentionally ignored so providers can pass
/// through newer draft keywords without making the common path unusable.
pub fn validate_json_schema(
  schema : Json,
  value : Json,
) -> Unit raise JsonSchemaValidationError {
  validate_json_schema_at(schema, value, "$")
}

///|
/// Return whether a JSON value satisfies a schema without raising.
pub fn json_schema_matches(schema : Json, value : Json) -> Bool {
  schema_matches(schema, value)
}

///|
/// AI SDK-style camel-case aliases for the schema boundary.
pub fn validateJsonSchema(
  schema : Json,
  value : Json,
) -> Unit raise JsonSchemaValidationError {
  validate_json_schema(schema, value)
}

///|
/// Return whether a JSON value satisfies a schema without raising.
pub fn jsonSchemaMatches(schema : Json, value : Json) -> Bool {
  json_schema_matches(schema, value)
}

///|
/// Normalize a JSON Schema definition; boolean schemas pass through.
fn openai_normalize_schema_definition(
  schema : Json,
  removed_property_names : Ref[Bool],
) -> Json raise {
  match schema {
    True | False | Null => schema
    _ => openai_normalize_schema_body(schema, removed_property_names)
  }
}

///|
/// Normalize a JSON Schema for OpenAI structured outputs.
///
/// OpenAI rejects the JSON Schema `propertyNames` keyword. Property names in
/// JSON objects are always strings, so a string-schema constraint is dropped
/// and left to client-side validation; any other `propertyNames` schema is
/// rejected. Recursion covers every subschema position OpenAI can observe.
fn openai_normalize_schema_body(
  schema : Json,
  removed_property_names : Ref[Bool],
) -> Json raise {
  guard schema is Object(fields) else { return schema }
  if fields.get("propertyNames") is Some(property_names) {
    guard property_names is { "type": String("string"), .. } else {
      raise @provider.UnsupportedFunctionalityError(
        functionality="JSON Schema propertyNames that does not use a string schema",
      )
    }
    removed_property_names.val = true
  }
  let normalized = @provider.copy_provider_metadata(fields)
  normalized.remove("propertyNames")
  // Subschemas nested under record keywords.
  for keyword in ["properties", "patternProperties", "definitions", "$defs"] {
    match normalized.get(keyword) {
      Some(Object(record)) => {
        let mapped : Map[String, Json] = Map([])
        for entry in record.iter2() {
          mapped[entry.0] = openai_normalize_schema_definition(
            entry.1,
            removed_property_names,
          )
        }
        normalized[keyword] = Json::object(mapped)
      }
      _ => ()
    }
  }
  // Single subschema positions.
  for
    keyword in [
      "additionalProperties", "additionalItems", "contains", "not", "if", "then",
      "else",
    ] {
    match normalized.get(keyword) {
      Some(value) =>
        normalized[keyword] = openai_normalize_schema_definition(
          value, removed_property_names,
        )
      None => ()
    }
  }
  // Array-valued subschemas.
  for keyword in ["items", "allOf", "anyOf", "oneOf"] {
    match normalized.get(keyword) {
      Some(Array(values)) =>
        normalized[keyword] = Json::array(
          [
            for value in values => {
              openai_normalize_schema_definition(value, removed_property_names)
            }
          ],
        )
      Some(value) =>
        if keyword == "items" {
          normalized[keyword] = openai_normalize_schema_definition(
            value, removed_property_names,
          )
        }
      None => ()
    }
  }
  Json::object(normalized)
}

///|
/// Normalize a strict schema and record a compatibility warning when a
/// `propertyNames` constraint had to be dropped.
fn openai_normalize_strict_schema(
  schema : Json,
  warnings : Array[@provider.Warning],
) -> Json raise {
  let removed_property_names = Ref(false)
  let normalized = openai_normalize_schema_body(schema, removed_property_names)
  if removed_property_names.val {
    warnings.push(
      @provider.Warning::Compatibility(
        feature="JSON Schema propertyNames",
        details="OpenAI does not support JSON Schema propertyNames. It was removed before sending the schema, so OpenAI will not enforce property-name constraints.",
      ),
    )
  }
  normalized
}

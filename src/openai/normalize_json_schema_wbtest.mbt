///|
test "strict schema normalization drops string propertyNames" {
  let warnings : Array[@provider.Warning] = []
  let normalized = openai_normalize_strict_schema(
    {
      "type": "object",
      "propertyNames": { "type": "string" },
      "properties": {
        "nested": {
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "propertyNames": { "type": "string" },
          },
        },
      },
    },
    warnings,
  )
  guard normalized is Object(fields) else { fail("expected object") }
  assert_false(fields.contains("propertyNames"))
  // Removals collapse into a single compatibility warning.
  assert_eq(warnings.length(), 1)
  assert_true(
    warnings[0]
    is @provider.Warning::Compatibility(feature="JSON Schema propertyNames", ..),
  )
}

///|
test "strict schema normalization rejects non-string propertyNames" {
  let warnings : Array[@provider.Warning] = []
  try
    openai_normalize_strict_schema(
      { "propertyNames": { "type": "integer" } },
      warnings,
    )
  catch {
    @provider.UnsupportedFunctionalityError(..) => ()
    error => fail("unexpected error")
  } noraise {
    _ => fail("expected unsupported functionality error")
  }
}

///|
test "strict schema normalization leaves plain schemas untouched" {
  let warnings : Array[@provider.Warning] = []
  let schema : Json = {
    "type": "object",
    "properties": { "name": { "type": "string" } },
    "required": ["name"],
  }
  assert_eq(openai_normalize_strict_schema(schema, warnings), schema)
  assert_eq(warnings.length(), 0)
}

///|
test "JSON Schema validates nested structured output" {
  let schema : Json = {
    "type": "object",
    "required": ["name", "scores"],
    "properties": {
      "name": { "type": "string", "minLength": 2 },
      "scores": {
        "type": "array",
        "minItems": 1,
        "uniqueItems": true,
        "items": { "type": "integer", "minimum": 0 },
      },
    },
    "additionalProperties": false,
  }
  let value : Json = { "name": "MoonBit", "scores": [1, 2, 3] }
  validate_json_schema(schema, value)
  assert_true(json_schema_matches(schema, value))
  assert_true(jsonSchemaMatches(schema, value))
}

///|
test "JSON Schema reports the nested path for invalid output" {
  let schema : Json = {
    "type": "object",
    "required": ["items"],
    "properties": {
      "items": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["name"],
          "properties": { "name": { "type": "string" } },
          "additionalProperties": false,
        },
      },
    },
  }
  let value : Json = { "items": [{ "name": 42 }] }
  try validate_json_schema(schema, value) catch {
    JsonSchemaValidationError(path~, message~) => {
      assert_eq(path, "$.items[0].name")
      assert_eq(message, "value has the wrong JSON type")
    }
  } noraise {
    _ => fail("expected schema validation to fail")
  }
  assert_true(!json_schema_matches(schema, value))
}

///|
test "JSON Schema supports boolean and composition schemas" {
  let schema : Json = {
    "allOf": [
      { "type": "number", "minimum": 1 },
      { "anyOf": [{ "const": 2 }, { "const": 4 }] },
    ],
    "not": { "const": 3 },
  }
  validateJsonSchema(schema, 4)
  assert_true(json_schema_matches(schema, 2))
  assert_true(!json_schema_matches(schema, 3))
  assert_true(!json_schema_matches(schema, 5))
  assert_true(json_schema_matches(true, { "anything": [1, 2] }))
  assert_true(!json_schema_matches(false, null))
}

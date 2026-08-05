///|
test "Anthropic sanitizes constraints and unsupported formats" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "interval": {
        "type": "number",
        "minimum": 1,
        "maximum": 60,
        "exclusiveMinimum": 0,
        "exclusiveMaximum": 120,
      },
      "slug": {
        "type": "string",
        "description": "A URL slug",
        "minLength": 1,
        "maxLength": 20,
        "pattern": "^[a-z0-9-]+$",
        "format": "regex",
      },
    },
    "required": ["interval", "slug"],
    "additionalProperties": false,
  }
  let sanitized = sanitize_json_schema(schema)
  assert_eq(
    sanitized,
    (
      {
        "type": "object",
        "properties": {
          "interval": {
            "type": "number",
            "description": "minimum: 1; maximum: 60; exclusive minimum: 0; exclusive maximum: 120.",
          },
          "slug": {
            "type": "string",
            "description": "A URL slug\nmin length: 1; max length: 20; pattern: ^[a-z0-9-]+$; format: regex.",
          },
        },
        "additionalProperties": false,
        "required": ["interval", "slug"],
      } : Json),
  )
  assert_true(schema.stringify().contains("exclusiveMinimum"))
}

///|
test "Anthropic sanitizes recursive definitions and oneOf" {
  let schema : Json = {
    "oneOf": [
      { "type": "string", "minLength": 1 },
      { "type": "number", "minimum": 0 },
    ],
    "$defs": { "PositiveInteger": { "type": "integer", "minimum": 1 } },
    "type": "object",
    "properties": {
      "count": { "$ref": "#/$defs/PositiveInteger" },
      "tags": {
        "type": "array",
        "minItems": 2,
        "maxItems": 4,
        "uniqueItems": true,
        "items": {
          "anyOf": [
            { "type": "string", "minLength": 1 },
            { "type": "number", "maximum": 10 },
          ],
        },
      },
    },
  }
  let sanitized = sanitizeJsonSchema(schema)
  match sanitized {
    {
      "anyOf": Array(choices),
      "$defs": {
        "PositiveInteger": {
          "type": "integer",
          "description": "minimum: 1.",
          ..
        },
        ..
      },
      "properties": {
        "count": { "$ref": "#/$defs/PositiveInteger", .. },
        "tags": {
          "items": { "anyOf": Array(items), .. },
          "description": "min items: 2; max items: 4; unique items: true.",
          ..
        },
        ..
      },
      "additionalProperties": False,
      ..
    } => {
      assert_eq(choices.length(), 2)
      assert_eq(items.length(), 2)
    }
    _ => fail("sanitized composition schema has an unexpected shape")
  }
}

///|
test "Anthropic preserves supported formats and references" {
  let schema : Json = {
    "type": "string",
    "$ref": "#/definitions/Email",
    "format": "email",
    "minLength": 1,
  }
  assert_eq(
    sanitize_json_schema(schema),
    ({ "$ref": "#/definitions/Email" } : Json),
  )
  assert_eq(
    sanitize_json_schema({ "type": "string", "format": "email" }),
    ({ "type": "string", "format": "email" } : Json),
  )
}

///|
fn require_name(value : Json) -> String raise {
  match value {
    Object(fields) =>
      match fields.get("name") {
        Some(String(name)) => name
        _ => fail("name must be a string")
      }
    _ => fail("value must be an object")
  }
}

///|
test "parseJSON preserves valid JSON and typed syntax diagnostics" {
  assert_eq(parseJSON("{\"name\":\"MoonBit\"}"), ({ "name": "MoonBit" } : Json))
  try parse_json("{\"name\":") catch {
    @provider.JSONParseError(text~, cause~) => {
      assert_eq(text, "{\"name\":")
      assert_true(cause.length() > 0)
      let message = @provider.JSONParseError(text~, cause~).message()
      assert_true(message.contains("JSON parsing failed"))
      assert_true(message.contains("{\"name\":"))
    }
  } noraise {
    _ => fail("expected a typed JSON parse error")
  }
}

///|
test "safeParseJSON distinguishes syntax failure without raising" {
  match safeParseJSON("[1,2,3]") {
    ParseJsonSuccess(value~, raw_value~) => {
      assert_eq(value, ([1, 2, 3] : Json))
      assert_eq(raw_value, value)
    }
    _ => fail("expected valid JSON")
  }
  match safe_parse_json("not-json") {
    ParseJsonFailure(error~, raw_value=None) =>
      match error {
        @provider.JSONParseError(text~, ..) => assert_eq(text, "not-json")
      }
    _ => fail("expected a safe JSON parse failure")
  }
  assert_true(isParsableJson("null"))
  assert_false(is_parsable_json("undefined"))
}

///|
test "validateTypes adds field and entity context" {
  let context = @provider.TypeValidationContext::new(
    field="message.metadata",
    entity_name="tool",
    entity_id="call-1",
  )
  assert_eq(
    validateTypes({ "name": "search" }, require_name, context~),
    "search",
  )
  match safe_validate_types({ "name": 42 }, require_name, context~) {
    TypeValidationFailure(error~, raw_value~) => {
      assert_eq(raw_value, ({ "name": 42 } : Json))
      match error {
        @provider.TypeValidationError(value~, cause~, context=Some(actual)) => {
          assert_eq(value, raw_value)
          assert_true(cause.contains("name must be a string"))
          assert_eq(actual, context)
          let message = @provider.TypeValidationError(
            value~,
            cause~,
            context=Some(actual),
          ).message()
          assert_true(message.contains("message.metadata"))
          assert_true(message.contains("tool, id: \"call-1\""))
        }
        _ => fail("expected validation context")
      }
    }
    _ => fail("expected safe type validation failure")
  }
}

///|
test "parse JSON with validation keeps syntax and validation failures separate" {
  match safeParseJSONWith("{\"name\":12}", require_name) {
    ParseJsonValidationFailure(error~, raw_value~) => {
      assert_eq(raw_value, ({ "name": 12 } : Json))
      assert_true(error.message().contains("name must be a string"))
    }
    _ => fail("expected a validation failure")
  }
  match safe_parse_json_with("{", require_name) {
    ParseJsonFailure(error~, raw_value=None) =>
      assert_true(error.message().contains("JSON parsing failed"))
    _ => fail("expected a syntax failure")
  }
}

///|
test "validateTypes preserves an equivalent typed validation error" {
  let value : Json = { "name": 1 }
  let context = @provider.TypeValidationContext::new(field="name")
  let validator : (Json) -> String raise = input => {
    raise @provider.TypeValidationError::new(
      value=input,
      cause="already typed",
      context~,
    )
  }
  try validate_types(value, validator, context~) |> ignore catch {
    @provider.TypeValidationError(
      cause="already typed",
      context=Some(actual),
      ..
    ) => assert_eq(actual, context)
    error => fail("unexpected validation error: \{@debug.to_string(error)}")
  } noraise {
    _ => fail("expected a preserved validation error")
  }
}

///|
test "provider default empty and no-content errors match AI SDK messages" {
  assert_true(
    @provider.EmptyResponseBodyError::new()
    is @provider.EmptyResponseBodyError(message="Empty response body"),
  )
  assert_true(
    @provider.NoContentGeneratedError::new()
    is @provider.NoContentGeneratedError(message="No content generated."),
  )
}
